# Harness-Agnostic Agent Backend

## Status: Backlog
## Priority: 10

## TL;DR

> **Quick Summary**: Extract `claude_agent_sdk` from the pykoclaw core into a
> `pykoclaw-claude` plugin and define an `AgentBackend` protocol so alternative
> coding agent harnesses (Pi, OpenCode, Codex CLI, Goose, etc.) can be plugged
> in as backends. The current architecture is already 80% there — process
> isolation via subprocess workers, JSON-newline pipes, and a clean plugin
> system. The actual SDK surface area is small: 4 files, ~5 imported types,
> 2 utility functions. Pi (`badlogic/pi-mono`) and OpenCode are the two
> strongest alternative backend candidates.
>
> **Estimated Effort**: Medium
> **Depends On**: (none)

---

## Motivation

Pykoclaw's core package (`pykoclaw`) currently hard-depends on
`claude-agent-sdk`. This means:

1. **Vendor lock-in** — every agent session must go through Claude Code CLI.
   No way to test alternative models (Kimi K2.5, GPT-4.1) via their native
   harnesses, or route different workspaces to different backends.
2. **Core bloat** — the core carries SDK message types, stream consumption
   logic, and MCP tool wrappers that only matter if the backend is Claude.
3. **Plugin asymmetry** — channel plugins (WhatsApp, Matrix, Slack) are
   properly decoupled via the `PykoClawPlugin` protocol, but the agent
   execution backend is hardcoded in core. This is the last major coupling.

Extracting the SDK into a plugin makes pykoclaw a **truly backend-agnostic
agent orchestrator**: bridges bring messages in, the backend protocol sends
them to whichever coding agent is configured, results flow back out.

## Current SDK surface area

The `claude_agent_sdk` dependency touches **4 files across 3 packages**:

| File | Package | Imports |
|------|---------|---------|
| `agent_core.py` | pykoclaw (core) | `ClaudeAgentOptions`, `ClaudeSDKClient`, `ResultMessage` |
| `sdk_consume.py` | pykoclaw (core) | `ClaudeSDKClient`, `AssistantMessage`, `ResultMessage`, `TextBlock`, `ToolUseBlock` |
| `tools.py` | pykoclaw (core) | `create_sdk_mcp_server`, `@tool` |
| `worker.py` | pykoclaw-acp | `ClaudeAgentOptions`, `ClaudeSDKClient`, `ResultMessage` |
| `dispatch.py` | pykoclaw-messaging | `ProcessError` (single exception import) |

The interaction pattern is uniform everywhere:

```python
options = ClaudeAgentOptions(cwd=..., model=..., mcp_servers=..., resume=...)
async with ClaudeSDKClient(options) as client:
    await client.query(prompt)
    async for message in client.receive_response():
        # AssistantMessage → TextBlock / ToolUseBlock
        # ResultMessage → session_id + result text
```

## Proposed architecture

### 1. AgentBackend protocol (core)

Define in `pykoclaw/src/pykoclaw/backend.py`:

```python
from __future__ import annotations
from dataclasses import dataclass
from collections.abc import AsyncGenerator
from typing import Any, Literal, Protocol, runtime_checkable

@dataclass
class AgentEvent:
    """Unified event yielded by any backend."""
    type: Literal["text", "tool_use", "result"]
    text: str | None = None
    session_id: str | None = None

@runtime_checkable
class AgentBackend(Protocol):
    async def query(
        self,
        prompt: str,
        *,
        cwd: str,
        model: str | None = None,
        system_prompt: str | None = None,
        resume_session_id: str | None = None,
        mcp_servers: dict[str, Any] | None = None,
        allowed_tools: list[str] | None = None,
        env: dict[str, str] | None = None,
    ) -> AsyncGenerator[AgentEvent, None]: ...
```

### 2. Backend discovery via plugin protocol

Extend `PykoClawPlugin` with one new hook:

```python
class PykoClawPlugin(Protocol):
    # ... existing hooks ...
    def get_backend(self) -> AgentBackend | None:
        """Return an agent backend, or None if this plugin doesn't provide one."""
        ...
```

Core selects the first plugin that returns a backend (or falls back to a
built-in default during migration).

### 3. pykoclaw-claude plugin

New package `pykoclaw-claude/` containing:
- Everything currently in `sdk_consume.py` (SDK message parsing)
- The `ClaudeAgentOptions`/`ClaudeSDKClient` wrapper implementing `AgentBackend`
- The MCP tool helpers (`create_sdk_mcp_server`, `@tool`)
- The `ProcessError` exception handling

```
pykoclaw-claude/
├── pyproject.toml           # depends on claude-agent-sdk
└── src/pykoclaw_claude/
    ├── __init__.py           # ClaudePlugin(PykoClawPluginBase)
    ├── backend.py            # ClaudeBackend(AgentBackend) — wraps SDK
    ├── sdk_consume.py        # moved from core
    └── mcp_tools.py          # create_sdk_mcp_server, @tool wrappers
```

### 4. MCP tool decoupling

This is the trickiest piece. Currently `tools.py` uses SDK-specific helpers:

```python
from claude_agent_sdk import create_sdk_mcp_server, tool
```

**Option A (minimal)**: Keep `tools.py` in core but have it return a
backend-agnostic tool definition dict. The backend plugin wraps these into
its native format (SDK's `create_sdk_mcp_server` for Claude, native MCP for
OpenCode, etc.).

**Option B (clean)**: Use the `mcp` library directly to create a standalone
MCP server. Any backend that supports MCP (Claude Code, OpenCode, Goose,
Codex) connects to it natively. This is the better long-term answer.

**Recommendation**: Option B — it aligns with the existing architecture where
plugin MCP servers are already passed as config dicts to the backend.

## Alternative backend candidates

Research identified these as viable replacements:

| Harness | Subprocess API | Session Resume | MCP Support | Multi-model | Assessment |
|---------|---------------|----------------|-------------|-------------|------------|
| **Pi** (`badlogic/pi-mono`) | RPC over stdio (JSON lines) | Yes (JSONL session files, `--continue`/`--resume`/`--session`) | Via extensions (MCP adapter exists) | Any LLM (OpenAI, Anthropic, Google, etc.) | **Strong candidate** — rich RPC protocol, multi-provider, active ecosystem |
| **OpenCode** | ACP over stdio | Yes | Native | Any LLM | **Strong candidate** — speaks ACP natively, same subprocess model |
| **Codex CLI** | JSONL streaming | Conversation IDs | Limited | OpenAI models | Good — similar pipe model |
| **Goose** | CLI + JSONL | Session files | Extensions | Multi-provider | Good — well-structured |
| **Cline CLI 2.0** | `--acp` flag | Yes | Native MCP | Multi-provider | Promising, very new |
| **Aider** | `--message` flag | Chat history files | No MCP | Multi-provider | Moderate — no MCP support |

### Pi Coding Agent — detailed assessment

**Repo**: `badlogic/pi-mono` (TypeScript monorepo, `@mariozechner/pi-coding-agent`)

Pi is an open-source, aggressively extensible coding agent CLI by Mario
Zechner. It's the strongest candidate alongside OpenCode.

**Why Pi fits well:**

1. **RPC mode (`--mode rpc`)** — purpose-built for process integration.
   Speaks JSON lines over stdin/stdout with a rich, documented protocol
   (`docs/rpc.md`). Pykoclaw's worker subprocess model maps directly:
   spawn `pi --mode rpc --no-session`, send `prompt` commands, receive
   `message_update`/`agent_end` events.

2. **Multi-provider LLM support** — `@mariozechner/pi-ai` provides a unified
   API across OpenAI, Anthropic, Google, and others. Model selection is a
   simple `--provider`/`--model` flag or RPC `set_model` command. This means
   a single `pykoclaw-pi` plugin could access all providers.

3. **Session management** — sessions persist as JSONL files with tree-based
   branching. RPC exposes `new_session`, `switch_session`, `fork`,
   `get_state`. Maps cleanly to pykoclaw's `resume_session_id` concept.

4. **Extension system** — TypeScript extensions can register tools, intercept
   events, add UI. An MCP adapter (`pi-mcp-adapter`) already exists. Custom
   tools can be added at runtime, so pykoclaw's schedule/list/cancel tools
   could be injected via an extension or MCP.

5. **Built-in tools match** — `read`, `bash`, `edit`, `write`, `grep`,
   `find`, `ls` mirror Claude Code's tool set. `--tools` flag controls which
   are enabled, analogous to `allowed_tools`.

6. **Thinking levels** — `--thinking off|minimal|low|medium|high|xhigh` maps
   to extended thinking budgets. Controllable per-turn via RPC.

7. **Context management** — `/compact` and `set_auto_compaction` handle long
   conversations. Session stats (tokens, cost) available via RPC.

**Mapping Pi RPC → pykoclaw `AgentEvent`:**

| Pi RPC event | → | `AgentEvent` |
|-------------|---|--------------|
| `message_update` with `text_delta` | → | `AgentEvent(type="text", text=delta)` |
| `tool_execution_start` | → | `AgentEvent(type="tool_use")` |
| `agent_end` | → | `AgentEvent(type="result", session_id=..., text=last_text)` |

**Mapping pykoclaw concepts → Pi RPC commands:**

| pykoclaw | → | Pi RPC |
|----------|---|--------|
| `query(prompt)` | → | `{"type": "prompt", "message": prompt}` |
| `resume_session_id` | → | `{"type": "switch_session", "path": session_file}` |
| `model` | → | `{"type": "set_model", "provider": ..., "modelId": ...}` |
| `system_prompt` | → | `.pi/SYSTEM.md` or `APPEND_SYSTEM.md` in cwd |
| `mcp_servers` | → | MCP adapter extension or `--extension` flag |
| `allowed_tools` | → | `--tools read,bash,edit,write` |

**Gaps / challenges:**

- **MCP is indirect** — Pi doesn't have native MCP server config like Claude
  Code's `mcp_servers` option. The `pi-mcp-adapter` extension bridges MCP,
  but injecting pykoclaw's dynamic MCP servers (schedule_task, etc.)
  per-session may require writing a small Pi extension or using the MCP
  adapter's config.
- **System prompt injection** — Pi reads `SYSTEM.md` files from disk rather
  than accepting a system prompt string via RPC. The plugin would need to
  write a `.pi/SYSTEM.md` in the conversation's cwd before launching.
- **TypeScript runtime** — Pi needs Node.js/Bun. Not a blocker (gogo has
  both), but adds a runtime dependency compared to Claude Code's standalone
  binary.
- **Session file format** — Pi uses JSONL with tree-based branching.
  pykoclaw stores only the session ID string. The plugin would need to map
  between pykoclaw's opaque ID and Pi's session file path.

**Verdict: highly feasible.** Pi's RPC mode is explicitly designed for the
exact use case pykoclaw needs — driving a coding agent from another process.
The protocol is richer than what pykoclaw requires (we only need
prompt/events/session, not thinking levels or compaction), which means the
mapping is straightforward with room to grow.

**OpenCode and Pi are the two strongest candidates**, with complementary
strengths: OpenCode speaks ACP natively (zero protocol translation needed
for pykoclaw-acp), while Pi has the richer RPC protocol and wider model
support.

## Implementation phases

### Phase 1 — Extract SDK to plugin (pure refactor)

**Goal**: Remove `claude-agent-sdk` from core `pyproject.toml`. Zero
behaviour change.

1. Define `AgentBackend` protocol + `AgentEvent` in core
2. Add `get_backend()` hook to `PykoClawPlugin` protocol (default: `None`)
3. Create `pykoclaw-claude` package, move SDK code there
4. Refactor `agent_core.py` to use the protocol
5. Refactor `worker.py` to use the protocol (or keep as Claude-specific in plugin)
6. Update `dispatch.py` to catch a backend-agnostic error instead of `ProcessError`
7. Update workspace `pyproject.toml` — core drops `claude-agent-sdk`, plugin adds it

**Effort**: ~2 days
**Risk**: Low — straightforward extraction, existing tests cover behaviour

### Phase 2 — Second backend: Pi or OpenCode (proof of concept)

**Goal**: Route a test workspace through an alternative harness.

**Option A — Pi** (`pykoclaw-pi`):
1. Create `pykoclaw-pi` package implementing `AgentBackend`
2. Spawn `pi --mode rpc --no-session` as subprocess
3. Map RPC `prompt`→`message_update`→`agent_end` to `AgentEvent` stream
4. Handle session resume via Pi's `switch_session` RPC command
5. Inject pykoclaw MCP tools via `pi-mcp-adapter` extension or `.pi/SYSTEM.md`
6. Configure one workspace to use Pi backend with a non-Claude model

**Option B — OpenCode** (`pykoclaw-opencode`):
1. Create `pykoclaw-opencode` package implementing `AgentBackend`
2. Map OpenCode's ACP messages to `AgentEvent`
3. Handle session resume via OpenCode's state management
4. Test MCP tool injection (OpenCode supports MCP natively)
5. Configure one workspace to use OpenCode backend

**Effort**: ~2–3 days (either option)
**Risk**: Medium — protocol mapping, MCP injection quirks

### Phase 3 — MCP decoupling (if needed)

**Goal**: Replace `create_sdk_mcp_server`/`@tool` with standalone MCP server.

1. Rewrite `tools.py` using the `mcp` library directly
2. Each backend connects to the MCP server via its native mechanism
3. Plugin MCP servers (WhatsApp, Matrix, etc.) keep working unchanged

**Effort**: ~1 day
**Risk**: Low — MCP protocol is standard, just changing the wrapper

## What changes in core

After Phase 1, the core has:

| File | Change |
|------|--------|
| `backend.py` | **New** — `AgentBackend` protocol + `AgentEvent` dataclass (~30 lines) |
| `plugins.py` | **Modified** — add `get_backend()` to protocol + base class (~5 lines) |
| `agent_core.py` | **Modified** — use `AgentBackend` instead of `ClaudeSDKClient` directly |
| `tools.py` | **Modified** — remove `claude_agent_sdk` imports, use `mcp` library or agnostic dict |
| `sdk_consume.py` | **Removed** — moved to `pykoclaw-claude` |
| `pyproject.toml` | **Modified** — drop `claude-agent-sdk` dependency |

The `pykoclaw-messaging` dispatch layer and all channel plugins remain
**untouched** — they already talk through `query_agent()` and don't touch
the SDK directly (except `ProcessError` in `dispatch.py`, which gets a
backend-agnostic replacement).

## Key risks and mitigations

1. **MCP tool injection** — backends need different mechanisms for MCP server
   config. Mitigation: the `AgentBackend.query()` signature accepts
   `mcp_servers: dict` — each backend interprets this in its native way.

2. **Session resume semantics** — Claude uses session files, OpenCode has its
   own state, Goose uses session files differently. Mitigation: the protocol
   uses an opaque `resume_session_id: str | None` — each backend maps this to
   its own resume mechanism.

3. **allowed_tools permission model** — Claude Code has `bypassPermissions` +
   allowed_tools list; other backends have different safety models. Mitigation:
   pass `allowed_tools` as optional hint; backends that don't support it
   ignore it (or use their native equivalent).

4. **Streaming format differences** — each backend streams differently.
   Mitigation: `AgentEvent` is deliberately simple (text | tool_use | result)
   — easy to map from any backend's native format.

## Open decisions

- [ ] Should backend selection be per-workspace or global? Per-workspace is
      more flexible (different agents use different backends) but adds config
      complexity.
- [ ] How to handle MCP tool registration if the backend doesn't support MCP?
      Fall back to injecting tools as system prompt instructions?
- [ ] Should `AgentEvent.tool_use` carry the tool name/args for observability,
      or just be a signal for the "pending separator" logic in streaming?
- [ ] Worker subprocess ownership: should the `WorkerPool` live in core or in
      each backend plugin? Currently it's in `pykoclaw-acp` (which would
      become backend-specific).

## Related plans

- [sandbox-plugin.md] — depends on harness-agnostic workers; sandbox wraps
  whatever backend subprocess is used
- [core-simplification.md] — could be done before or after; no conflict
- [messaging-shared-code-phase1.md] — Phase 1 messaging refactor is
  independent but touches adjacent code

[sandbox-plugin.md]: sandbox-plugin.md
[core-simplification.md]: core-simplification.md
[messaging-shared-code-phase1.md]: messaging-shared-code-phase1.md
