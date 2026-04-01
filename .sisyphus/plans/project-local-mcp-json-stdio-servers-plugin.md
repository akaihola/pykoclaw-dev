# Repo-Local `.mcp.json` Stdio Servers – Plugin-Based Approach

## Status: Done

## Completed: 2026-04-01

## Priority: 5

## TL;DR

> **Quick Summary**: Same user-visible problem as the [core-based plan] –
> workspace `.mcp.json` stdio servers are invisible to pykoclaw sessions. This
> alternative implements the feature as a **separate plugin package**
> (`pykoclaw-mcp-json`) rather than adding a helper module to the core
> `pykoclaw` package. The plugin uses the existing `get_mcp_servers()` hook to
> inject servers discovered from `$PYKOCLAW_DATA/.mcp.json`, keeping the core
> untouched.
>
> **Deliverables**:
>
> - New workspace member `pykoclaw-mcp-json/` with its own `pyproject.toml`,
>   entry point, and test suite
> - Plugin class `McpJsonPlugin(PykoClawPluginBase)` that reads, validates, and
>   returns stdio servers via `get_mcp_servers()`
> - Tests for missing file, malformed JSON, stdio filtering, name-collision
>   warnings, and end-to-end integration
> - Documentation in the new package's `README.md` and a note in the root
>   `pykoclaw/README.md`
>
> **Estimated Effort**: Short
> **Parallel Execution**: NO
> **Depends On**: —

---

## Context

Identical to the [core-based plan] – see that document for the user-visible
problem, current code path, `.mcp.json` shape, and scope decision.

The key architectural question is **where** the `.mcp.json` loading logic
lives:

| Aspect          | Core approach                            | Plugin approach (this plan)                      |
| --------------- | ---------------------------------------- | ------------------------------------------------ |
| New code lives  | `pykoclaw/src/pykoclaw/mcp_config.py`    | `pykoclaw-mcp-json/src/pykoclaw_mcp_json/...`    |
| Core changes    | Import + merge call in `agent_core.py`   | None                                             |
| Merge semantics | Custom merge logic in `agent_core.py`    | Uses existing plugin `get_mcp_servers()` hook    |
| Activation      | Always active if pykoclaw is installed   | Active only when the plugin package is installed |
| Precedence      | Explicit 4-tier merge in `query_agent()` | Plugin-order-dependent (see Guardrails)          |

---

## Work Objectives

### Core Objective

Same as the core plan: make repo-local Claude Code stdio MCP servers available
inside pykoclaw sessions – but without touching `agent_core.py`.

### Concrete Deliverables

- New `pykoclaw-mcp-json` workspace package with entry point
  `pykoclaw.plugins = "pykoclaw_mcp_json:McpJsonPlugin"`
- Plugin reads `settings.data_dir / ".mcp.json"` in `get_mcp_servers()`
- Only stdio-compatible entries are returned
- Invalid or unsupported entries are skipped with a warning
- Name collisions with built-in or other plugin servers are logged (the
  existing `dict.update()` merge in `agent_core.py` means later plugins win,
  but the plugin should warn rather than silently shadow)
- README documents the feature, supported subset, and limitations

### Definition of Done

- [x] `pykoclaw-mcp` is a workspace member in the root `pyproject.toml`
- [x] The plugin entry point is registered and discovered by `load_plugins()`
- [x] stdio servers from `mcpServers` appear in `ClaudeAgentOptions.mcp_servers`
- [x] malformed or absent `.mcp.json` does not break the agent call
- [x] `uv run pytest pykoclaw-mcp/tests/ -v` passes (29 tests)
- [x] `uv run pytest pykoclaw/tests/ -v` still passes (130 tests, no core changes)

### Guardrails

- Do NOT modify `agent_core.py` or `plugins.py` in the core package.
- Do NOT import non-stdio servers in the first iteration.
- Do NOT abort the session because one repo-local MCP entry is malformed.
- The plugin SHOULD log a warning when its server names collide with
  already-known names, even though it cannot prevent the override in the
  current `dict.update()` merge semantics. A follow-up could add collision
  detection to the core merge loop.
- Do NOT broaden behavior to ACP worker pool in the same change.

---

## Implementation Plan

### Task 1: Scaffold the `pykoclaw-mcp-json` package

**Files:**

- Create: `pykoclaw-mcp-json/pyproject.toml`
- Create: `pykoclaw-mcp-json/src/pykoclaw_mcp_json/__init__.py`
- Modify: root `pyproject.toml` (add workspace member)

**Plan:**

1. Create the standard uv workspace package layout:
   ```
   pykoclaw-mcp-json/
   ├── pyproject.toml
   ├── src/
   │   └── pykoclaw_mcp_json/
   │       ├── __init__.py
   │       └── loader.py
   ├── tests/
   │   ├── __init__.py
   │   └── test_loader.py
   └── README.md
   ```
2. `pyproject.toml` declares:
   - `dependencies = ["pykoclaw"]`
   - entry point `[project.entry-points."pykoclaw.plugins"] mcp-json = "pykoclaw_mcp_json:McpJsonPlugin"`
3. Add `"pykoclaw-mcp-json"` to the root `pyproject.toml` workspace members.
4. Run `uv sync --all-packages`.

### Task 2: Implement the `.mcp.json` loader

**Files:**

- Create: `pykoclaw-mcp-json/src/pykoclaw_mcp_json/loader.py`
- Create: `pykoclaw-mcp-json/tests/test_loader.py`

**Plan:**

1. Add `load_stdio_servers(mcp_json_path: Path) -> dict[str, dict[str, Any]]`
   – a pure function that:
   - Returns `{}` silently if the file does not exist.
   - Returns `{}` with a warning if the JSON is malformed.
   - Iterates `mcpServers` entries.
   - Accepts entries with no `type` or `type == "stdio"`.
   - Requires `command` to be a non-empty string.
   - Accepts optional `args: list[str]` and `env: dict[str, str]`.
   - Strips Claude-Code-only keys (`alwaysAllow`, etc.).
   - Skips non-stdio or invalid entries with a warning.
2. Each accepted entry is returned as a dict matching the Claude Agent SDK
   stdio server shape: `{"command": ..., "args": [...], "env": {...}}`.
3. Investigate `${VAR}` env placeholder expansion (same as core plan).
4. Tests cover:
   - missing file → `{}`
   - valid stdio entry with implicit type
   - valid stdio entry with explicit type
   - non-stdio entries filtered out
   - malformed JSON → `{}` + warning
   - invalid entry shape → skipped + warning
   - Claude-Code-only keys stripped

### Task 3: Implement the plugin class

**Files:**

- Create/modify: `pykoclaw-mcp-json/src/pykoclaw_mcp_json/__init__.py`

**Plan:**

1. `McpJsonPlugin(PykoClawPluginBase)` overrides `get_mcp_servers()`:
   ```python
   def get_mcp_servers(self, db: DbConnection, conversation: str) -> dict[str, Any]:
       from pykoclaw.config import Settings
       settings = Settings()
       mcp_json_path = settings.data_dir / ".mcp.json"
       return load_stdio_servers(mcp_json_path)
   ```
2. The plugin has no commands, no migrations, no response transformers – only
   the MCP server hook.

### Task 4: Integration test

**Files:**

- Create: `pykoclaw-mcp-json/tests/test_integration.py`

**Plan:**

1. Write a test that installs the plugin, creates a `data_dir` with a valid
   `.mcp.json`, patches `ClaudeSDKClient`, calls `query_agent()`, and asserts
   the final `ClaudeAgentOptions.mcp_servers` contains:
   - the built-in `pykoclaw` server
   - the `.mcp.json` stdio server(s)
2. Test that malformed `.mcp.json` still allows the agent call to proceed.

### Task 5: Documentation

**Files:**

- Create: `pykoclaw-mcp-json/README.md`
- Modify: `pykoclaw/README.md` (add a pointer to the plugin)
- Optionally create: `pykoclaw/.memory/project-local-mcp-json.md`

**Plan:**

1. `pykoclaw-mcp-json/README.md` documents:
   - What the plugin does
   - Where the `.mcp.json` must live (`$PYKOCLAW_DATA/.mcp.json`)
   - Supported subset (stdio only, exact `cwd`, invalid entries skipped)
   - Installation: `uv add pykoclaw-mcp-json`
2. `pykoclaw/README.md` gets a one-line mention: "Install `pykoclaw-mcp-json`
   to auto-import repo-local `.mcp.json` stdio servers."

### Task 6: Verify

**Plan:**

1. `uv run pytest pykoclaw-mcp-json/tests/ -v`
2. `uv run pytest pykoclaw/tests/ -v` (no regressions)
3. `bin/update-backlog.sh`

---

## Merge Semantics

The existing `agent_core.py` merge loop is:

```python
mcp_servers = { "pykoclaw": built_in }   # 1. built-in
for plugin in plugins:
    mcp_servers.update(plugin.get_mcp_servers(...))  # 2. plugins (order-dependent)
if extra_mcp_servers:
    mcp_servers.update(extra_mcp_servers)  # 3. explicit overrides
```

The `.mcp.json` servers are injected at step 2 via the plugin hook. This means:

- They **can** shadow built-in servers (unlike the core plan which guards
  against this). The plugin mitigates this by logging a warning if it returns
  a server named `"pykoclaw"`, but cannot prevent the override.
- Plugin load order determines whether `.mcp.json` servers shadow or are
  shadowed by other plugin servers. Entry point ordering is
  non-deterministic across packages.
- `extra_mcp_servers` still wins (step 3), same as the core plan.

**Trade-off**: the core plan offers explicit, tested, 4-tier precedence. The
plugin plan inherits the existing merge loop – simpler to implement, but
collision semantics are weaker.

---

## Out of Scope

Same as the [core-based plan]:

- HTTP/SSE MCP servers
- Recursive parent-directory lookup
- ACP worker-pool changes
- MCP assembly architecture refactor
- Full Claude Code `.mcp.json` extension key support

[core-based plan]: project-local-mcp-json-stdio-servers.md
