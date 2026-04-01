# Repo-Local `.mcp.json` Stdio Servers Missing from pykoclaw Sessions

## Status: Done

## Completed: 2026-04-01

## Priority: 5

## TL;DR

> **Quick Summary**: A workspace can already define MCP tools for Claude Code in
> repo-local `.mcp.json`, but pykoclaw sessions ignore that file completely.
> The user sees tools available in Claude Code disappear when the same workspace
> is accessed through pykoclaw channels or scheduler tasks. Fix `query_agent()`
> so it reads `<cwd>/.mcp.json`, extracts `mcpServers` entries that are stdio
> servers, normalizes them to Claude Agent SDK config, and merges them into the
> runtime `mcp_servers` dict before `ClaudeAgentOptions` is created.
>
> **Deliverables**:
>
> - `pykoclaw/src/pykoclaw/mcp_config.py` helper for reading and validating
>   project-local `.mcp.json`
> - `pykoclaw/src/pykoclaw/agent_core.py` integration before
>   `ClaudeAgentOptions(...)`
> - Tests for missing file, malformed JSON, stdio filtering, merge precedence,
>   and end-to-end `ClaudeAgentOptions.mcp_servers` contents
> - `pykoclaw/README.md` note documenting automatic loading of
>   `$PYKOCLAW_DATA/.mcp.json`
>
> **Estimated Effort**: Short
> **Parallel Execution**: NO – parser behavior and merge precedence should be
> decided first, then wired into `query_agent()`
> **Depends On**: —
> **Pi-Session**: dbeda3e4-8024-46ee-a982-28dcf041db4e
> **Pi-Session-File**: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-04-01T06-11-17-296Z_dbeda3e4-8024-46ee-a982-28dcf041db4e.jsonl

---

## Context

### User-visible problem

A workspace may already have a Claude Code `.mcp.json` that exposes useful
repo-local tools. Today those tools work in direct Claude Code sessions, but
when the same workspace is used through pykoclaw the agent only sees:

- the built-in `pykoclaw` MCP server
- plugin-provided MCP servers
- anything passed explicitly via `extra_mcp_servers`

The repo-local `.mcp.json` tools never appear, so the workspace behaves
inconsistently depending on which harness launched the agent.

### Current code path

`pykoclaw/src/pykoclaw/agent_core.py` currently builds `mcp_servers` like this:

1. start with the built-in `pykoclaw` SDK server
2. merge plugin-provided servers from `load_plugins()`
3. merge any `extra_mcp_servers`
4. pass the final dict to `ClaudeAgentOptions(mcp_servers=...)`

The Claude Agent SDK can accept `mcp_servers` as either a dict or a path, but
pykoclaw currently always passes a dict and never points the SDK at
`data_dir/.mcp.json`.

### Known `.mcp.json` shape

Local examples in this environment use Claude Code's project-local format:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"],
      "env": {}
    }
  }
}
```

Important implications for pykoclaw:

- top-level key is `mcpServers`, not `mcp_servers`
- stdio servers are represented by `command`, optional `args`, optional `env`
- `type` may be absent or explicitly `"stdio"`
- workspace files may also contain Claude-Code-specific keys such as
  `alwaysAllow`, which should not become part of the SDK config we synthesize

### Scope decision

This backlog item is intentionally limited to **stdio** servers from the exact
`cwd` directory used by `query_agent()`.

That means:

- read only `data_dir / ".mcp.json"`
- do not walk parent directories looking for more config files
- do not import HTTP/SSE servers in this first pass
- do not change the independent ACP worker loop in
  `pykoclaw-acp/src/pykoclaw_acp/worker_pool.py`

`pykoclaw-chat`, scheduler tasks, and channel plugins that already go through
`query_agent()` will inherit the feature automatically.

---

## Work Objectives

### Core Objective

Make repo-local Claude Code stdio MCP servers available inside pykoclaw
sessions without breaking built-in or plugin-provided MCP behavior.

### Concrete Deliverables

- New helper that loads and validates `data_dir/.mcp.json`
- Only stdio-compatible server entries are converted into SDK config
- Invalid or unsupported entries are skipped with a warning instead of failing
  the session
- Merge order is explicit and tested
- README documents where the file must live and what subset is supported

### Definition of Done

- [ ] `query_agent()` reads `data_dir/.mcp.json` before creating
      `ClaudeAgentOptions`
- [ ] stdio servers from `mcpServers` are merged into `mcp_servers`
- [ ] built-in `pykoclaw` and plugin servers cannot be silently shadowed by a
      conflicting `.mcp.json` name
- [ ] `extra_mcp_servers` still wins when the caller explicitly supplies an
      override
- [ ] malformed or absent `.mcp.json` does not break the agent call
- [ ] `uv run pytest pykoclaw/tests/test_agent_core.py -v` passes
- [ ] `uv run pytest pykoclaw/tests/ -v` passes

### Guardrails

- Do NOT replace the whole runtime dict with a path-based `mcp_servers` value –
  pykoclaw still needs to inject its own in-process SDK MCP servers.
- Do NOT import non-stdio servers in the first iteration.
- Do NOT let `.mcp.json` override the built-in `pykoclaw` server name.
- Do NOT abort the whole session because one repo-local MCP entry is malformed.
- Do NOT broaden behavior to ACP worker pool in the same change unless a shared
  helper naturally makes that trivial and separately tested.

---

## Implementation Plan

### Task 1: Add a focused `.mcp.json` loader

**Files:**

- Create: `pykoclaw/src/pykoclaw/mcp_config.py`
- Create: `pykoclaw/tests/test_mcp_config.py`

**Plan:**

1. Add `load_project_stdio_mcp_servers(cwd: Path) -> dict[str, McpServerConfig]`
   in a dedicated helper module so JSON parsing and validation stay out of the
   main agent loop.
2. Read only `cwd / ".mcp.json"`.
3. Parse the top-level `mcpServers` mapping.
4. For each server entry:
   - accept entries with no `type` and entries with `type == "stdio"`
   - require `command` to be a non-empty string
   - accept optional `args: list[str]` and `env: dict[str, str]`
   - ignore Claude-Code-only keys such as `alwaysAllow`
   - skip `http` / `sse` / unknown `type` entries with a warning
5. If the file is missing, return `{}` silently.
6. If the JSON is malformed, log a warning and return `{}`.
7. Add focused tests for:
   - missing file
   - valid stdio entry with implicit type
   - valid stdio entry with explicit type
   - non-stdio entries filtered out
   - malformed JSON tolerated
   - invalid entry shape skipped

**Important investigation step:** before finalizing the helper, confirm whether
Claude Code-style `${VAR}` environment placeholders need explicit expansion when
pykoclaw converts `.mcp.json` into an SDK dict. If the SDK/CLI path does not do
this automatically for dict-based configs, add a small env expansion helper for
string values in the `env` map and cover it with tests. If it already works,
record that finding in the tests or a short memory note.

### Task 2: Merge project-local servers into `query_agent()`

**Files:**

- Modify: `pykoclaw/src/pykoclaw/agent_core.py`
- Modify: `pykoclaw/tests/test_agent_core.py`

**Plan:**

1. Import the new helper in `agent_core.py`.
2. Build merge order explicitly:
   - built-in `pykoclaw`
   - plugin servers
   - repo-local `.mcp.json` stdio servers
   - `extra_mcp_servers`
3. Use additive merge semantics for `.mcp.json` entries:
   - if a repo-local server name collides with an existing built-in or plugin
     server, keep the existing runtime server and log a warning or info line
   - if `extra_mcp_servers` provides the same name, let the explicit caller
     override win as it does today
4. Add `test_agent_core.py` coverage that patches `ClaudeSDKClient`, runs
   `query_agent()`, and asserts the final `ClaudeAgentOptions.mcp_servers`
   contains:
   - built-in server(s)
   - plugin server(s)
   - imported `.mcp.json` stdio server(s)
   - correct precedence on collisions
5. Add a regression test showing that malformed `.mcp.json` still allows the
   agent call to proceed and still passes built-in/plugin MCP servers through.

### Task 3: Document supported workspace behavior

**Files:**

- Modify: `pykoclaw/README.md`
- Optionally modify: `CLAUDE.md`
- Optionally create: `pykoclaw/.memory/project-local-mcp-json.md`

**Plan:**

1. Update the `pykoclaw/README.md` configuration or data-directory section to
   say that when `PYKOCLAW_DATA` points at a workspace root, pykoclaw will also
   read `$PYKOCLAW_DATA/.mcp.json` and import stdio servers from its
   `mcpServers` block.
2. Document the first-pass limitation clearly:
   - stdio only
   - exact `cwd` file only
   - invalid entries skipped with warnings
3. If implementation reveals a non-obvious gotcha such as env placeholder
   handling or merge precedence, capture it in a short memory note and update
   `pykoclaw/.memory/INDEX.md`.

### Task 4: Verify and regenerate backlog

**Files:**

- Modify indirectly: `.sisyphus/BACKLOG.md`

**Plan:**

1. Run focused tests first:
   - `uv run pytest pykoclaw/tests/test_mcp_config.py -v`
   - `uv run pytest pykoclaw/tests/test_agent_core.py -v`
2. Run full core test suite:
   - `uv run pytest pykoclaw/tests/ -v`
3. Regenerate backlog after plan/doc changes:
   - `bin/update-backlog.sh`

---

## Recommended Merge Semantics

Use this precedence unless testing or review proves a better rule is needed:

1. Built-in/runtime-generated servers are authoritative.
2. Repo-local `.mcp.json` is additive.
3. Explicit `extra_mcp_servers` overrides everything else.

This avoids a workspace config accidentally shadowing the in-process
`pykoclaw` SDK server or a plugin server that pykoclaw depends on for core
behavior, while still allowing callers to override deliberately through code.

---

## Out of Scope

- Importing HTTP or SSE MCP servers from `.mcp.json`
- Recursive parent-directory lookup for `.mcp.json`
- Reworking ACP worker-pool MCP configuration in the same change
- Moving all MCP assembly out of `agent_core.py` into a wider architecture pass
- Supporting every Claude Code `.mcp.json` extension key from day one
