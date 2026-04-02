# Session Resume Across Restarts

## Status: Done

## Completed: 2026-02-21

## Worktree: session-resume

## Priority: 3

## TL;DR

> **Quick Summary**: After a mitto-web restart, conversations lose Claude Code session history because pykoclaw-acp doesn't implement the ACP `session/load` protocol method. Mitto **already tries** `session/load` before falling back to `session/new` — but pykoclaw-acp doesn't advertise `loadSession` capability and doesn't handle the method. Fix: implement `session/load` in pykoclaw-acp, using the stored Claude Code session ID from the DB + `--resume`.
>
> **Deliverables** (pykoclaw-acp only — zero Mitto changes):
> - `server.py`: Advertise `loadSession: true` in `initialize` response; handle `session/load` method
> - `worker_protocol.py`: Add `resume_session_id` field to `WorkerConfig`
> - `worker_pool.py`: Accept `resume_session_id`, pass through to worker config
> - `worker.py`: Use `resume=config.resume_session_id` in `ClaudeAgentOptions`
> - Tests for the resume flow
>
> **Estimated Effort**: Short (2–3 hours)
> **Parallel Execution**: NO — sequential
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 → Task 5

---

## Context

### Problem

When `mitto-web` restarts (e.g., after deploying via `install-dev.sh`), existing conversations lose their Claude Code context. The agent forgets everything discussed, even though the Mitto UI shows a continuous thread.

### Root Cause

`install-dev.sh` restarts `mitto-web` to pick up new code. On restart, Mitto tries to reconnect each conversation to ACP. The ACP protocol has two session creation paths:

1. **`session/load`** — reload an existing session by its stored ACP session ID
2. **`session/new`** — create a fresh session

Mitto **already implements the client side** (`background_session.go:1198-1214`):
```go
// Try to load existing session if we have an ACP session ID and the agent supports it
if acpSessionID != "" && initResp.AgentCapabilities.LoadSession {
    loadResp, err := bs.acpConn.LoadSession(bs.ctx, acp.LoadSessionRequest{
        SessionId:  acp.SessionId(acpSessionID),
        Cwd:        cwd,
        McpServers: []acp.McpServer{},
    })
    if err == nil {
        bs.acpID = acpSessionID
        return nil  // Session resumed!
    }
    // Fall through to session/new
}
```

But pykoclaw-acp:
- Does **not** advertise `loadSession: true` in its `initialize` response
- Does **not** handle the `session/load` JSON-RPC method
- So Mitto skips `LoadSession` and always falls through to `session/new` → new UUID → new conversation dir → lost context

### What we already have

- **DB**: `upsert_conversation()` stores `(name, session_id, cwd)` where `session_id` is the Claude Code session ID
- **DB**: `get_conversation(name)` retrieves the stored session ID
- **Claude Agent SDK**: `ClaudeAgentOptions.resume` accepts a session ID → maps to `claude --resume <id>`
- **Mitto**: Already implements `LoadSession` client — just needs the agent to support it

### Why context wasn't lost before process isolation

Before process-isolated workers, `install-dev.sh` did NOT restart `mitto-web`. Editable installs (`uv tool install -e`) update code on disk, and the running ACP process kept its in-memory SDK clients alive. The restart was added as part of the process isolation work to ensure new worker subprocess code is loaded.

Both old (`ClientPool`) and new (`WorkerPool`) architectures derive conversation dirs from ACP session UUIDs the same way — the difference is purely that deployments now trigger restarts.

---

## Design

### Approach: Implement ACP `session/load`

The ACP protocol already defines the mechanism. We just need to implement the server side.

**Flow after fix:**
1. Mitto restarts, loads saved conversations
2. For each conversation, Mitto has stored `acpSessionID` (e.g., `"abc123-..."`)
3. Mitto spawns ACP process, calls `initialize`
4. pykoclaw-acp responds with `loadSession: true` ← **NEW**
5. Mitto calls `session/load` with `sessionId: "abc123-..."`
6. pykoclaw-acp looks up conversation `acp-abc123` in DB → finds Claude Code `session_id`
7. Worker spawned with `resume=<claude_code_session_id>` → Claude Code resumes with full history
8. If lookup fails → return error → Mitto falls back to `session/new` (graceful degradation)

### Edge cases

- **First-ever session**: No stored `acpSessionID` in Mitto → `session/new` → works as today
- **Session expired/corrupted**: `--resume` with stale ID → Claude Code falls back to fresh session → safe
- **Multiple concurrent conversations**: Each has a unique `acpSessionID` → each resumes independently
- **Old Mitto without `LoadSession` support**: Uses `session/new` → same as today (impossible — Mitto already has it)

---

## Work Objectives

### Core Objective

After a mitto-web restart, existing conversations resume with full Claude Code history — zero Mitto changes needed.

### Concrete Deliverables

- `pykoclaw-acp/src/pykoclaw_acp/server.py` — `loadSession` capability + `session/load` handler
- `pykoclaw-acp/src/pykoclaw_acp/worker_protocol.py` — `resume_session_id` in `WorkerConfig`
- `pykoclaw-acp/src/pykoclaw_acp/worker_pool.py` — Pass resume ID through to worker
- `pykoclaw-acp/src/pykoclaw_acp/worker.py` — Use `resume` in `ClaudeAgentOptions`
- `pykoclaw-acp/tests/` — Tests

### Definition of Done

- [ ] After restarting mitto-web, reopening a conversation resumes the previous Claude Code session
- [ ] New conversations (no prior history) work exactly as before
- [ ] Existing tests pass: `uv run pytest pykoclaw-acp/tests/ -v`
- [ ] New tests cover: session/load hit, session/load miss, resume passthrough

### Must Have

- `loadSession: true` in initialize response
- `session/load` handler that looks up prior session from DB
- Resume ID passed through to worker subprocess
- Worker uses `ClaudeAgentOptions(resume=...)` when resume ID is available
- Graceful error when session not found (Mitto falls back to `session/new`)

### Must NOT Have (Guardrails)

- MUST NOT modify Mitto (it already supports `LoadSession`)
- MUST NOT change the DB schema
- MUST NOT add conversation directory cleanup (separate concern)
- MUST NOT change `session/new` behavior at all

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**

### Test Decision

- **Infrastructure exists**: YES — pytest + pytest-asyncio
- **Automated tests**: YES (tests-after)
- **Framework**: pytest (via `uv run pytest`)
- **Manual verification**: Restart mitto-web, verify conversation continuity

---

## Execution Strategy

### Sequential Execution

All changes in pykoclaw-acp only. Sequential.

```
Task 1: Advertise loadSession capability + handle session/load in server
  ↓
Task 2: Add resume_session_id to WorkerConfig
  ↓
Task 3: Worker pool: accept + pass resume_session_id
  ↓
Task 4: Worker: use resume in ClaudeAgentOptions
  ↓
Task 5: Add tests
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1    | None       | 3      | 2                   |
| 2    | None       | 3, 4   | 1                   |
| 3    | 1, 2       | 5      | 4 (different file)  |
| 4    | 2          | 5      | 3 (different file)  |
| 5    | 3, 4       | None   | None (final)        |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agent |
|------|-------|-------------------|
| 1    | 1, 2  | Parallel — server + protocol, independent |
| 2    | 3, 4  | Parallel — pool + worker, different files |
| 3    | 5     | Tests |

---

## TODOs

- [ ] 1. Advertise `loadSession` capability and handle `session/load`

  **What to do**:

  In `server.py`:

  a) Add `loadSession: true` to initialize response:
  ```python
  async def _handle_initialize(self, msg_id, params):
      result = {
          "protocolVersion": PROTOCOL_VERSION,
          "agentCapabilities": {"loadSession": True},
          "agentInfo": {"name": "pykoclaw", "version": "0.1.0"},
      }
      self._write(self._protocol.format_response(msg_id, result))
  ```

  b) Add `session/load` to the dispatch table:
  ```python
  handler = {
      "initialize": self._handle_initialize,
      "session/new": self._handle_session_new,
      "session/load": self._handle_session_load,  # NEW
      "session/prompt": self._handle_session_prompt,
  }.get(method)
  ```

  c) Implement `_handle_session_load()`:
  ```python
  async def _handle_session_load(self, msg_id, params):
      session_id = params.get("sessionId", "")
      cwd = params.get("cwd", "")

      if not session_id:
          self._write(self._protocol.format_error(
              msg_id, JsonRpcError.INVALID_PARAMS, "sessionId is required"))
          return

      # Look up the conversation for this ACP session ID
      conversation_name = f"acp-{session_id[:8]}"
      conv = get_conversation(self._db, conversation_name)

      if not conv or not conv.session_id:
          self._write(self._protocol.format_error(
              msg_id, JsonRpcError.SESSION_ERROR,
              f"No prior session found for {session_id}"))
          return

      # Store session with resume info
      self._sessions[session_id] = {
          "cwd": cwd,
          "resume_session_id": conv.session_id,  # Claude Code session ID
      }
      self._write(self._protocol.format_response(msg_id, {}))
  ```

  d) In `_handle_session_prompt()`, pass `resume_session_id` from session dict to pool:
  ```python
  session = self._sessions[session_id]
  resume_id = session.pop("resume_session_id", None)  # Use once, then clear
  await self._pool.send(session_id, content, on_text=_send_chunk, resume_session_id=resume_id)
  ```

  **File**: `pykoclaw-acp/src/pykoclaw_acp/server.py`

  **Acceptance Criteria**:
  - [ ] `initialize` response includes `"loadSession": true` in `agentCapabilities`
  - [ ] `session/load` method handled, looks up conversation in DB
  - [ ] Returns error if session not found (Mitto falls back to `session/new`)
  - [ ] Existing tests pass (may need updating for new capability)

---

- [ ] 2. Add `resume_session_id` field to `WorkerConfig`

  **What to do**:
  - In `worker_protocol.py`, add `resume_session_id: str | None = None` to `WorkerConfig`
  - One-line addition. JSON-newline encoding handles `None` → `null` via defaults.

  **File**: `pykoclaw-acp/src/pykoclaw_acp/worker_protocol.py`

  **Acceptance Criteria**:
  - [ ] `WorkerConfig` has `resume_session_id: str | None = None`
  - [ ] Existing tests pass

---

- [ ] 3. Worker pool: accept and pass `resume_session_id`

  **What to do**:
  - Modify `send()` to accept optional `resume_session_id: str | None`
  - Pass it to `_spawn_worker()` (only used on first spawn for that session)
  - In `_spawn_worker()`, include it in `WorkerConfig`

  ```python
  async def send(self, session_id, prompt, *, on_text=None, resume_session_id=None):
      handle = await self._get_or_create(session_id, resume_session_id=resume_session_id)
      ...

  async def _get_or_create(self, session_id, *, resume_session_id=None):
      if session_id in self._entries:
          return self._entries[session_id]
      async with self._create_lock:
          if session_id in self._entries:
              return self._entries[session_id]
          handle = await self._spawn_worker(session_id, resume_session_id=resume_session_id)
          ...

  async def _spawn_worker(self, session_id, *, resume_session_id=None):
      ...
      config = WorkerConfig(
          ...,
          resume_session_id=resume_session_id,
      )
      ...
  ```

  **File**: `pykoclaw-acp/src/pykoclaw_acp/worker_pool.py`

  **Acceptance Criteria**:
  - [ ] `resume_session_id` flows from `send()` → `_spawn_worker()` → `WorkerConfig`
  - [ ] Existing tests pass

---

- [ ] 4. Worker: use `resume` in `ClaudeAgentOptions`

  **What to do**:
  ```python
  options = ClaudeAgentOptions(
      cwd=config.cwd,
      permission_mode="bypassPermissions",
      mcp_servers={"pykoclaw": mcp_server},
      model=config.model,
      cli_path=config.cli_path,
      allowed_tools=...,
      setting_sources=["project"],
      env={"SHELL": "/bin/bash"},
      resume=config.resume_session_id,  # NEW — None means fresh session
  )
  ```

  **File**: `pykoclaw-acp/src/pykoclaw_acp/worker.py`

  **Acceptance Criteria**:
  - [ ] `resume=config.resume_session_id` passed to `ClaudeAgentOptions`
  - [ ] Works normally when `resume_session_id` is `None`
  - [ ] Existing tests pass

---

- [ ] 5. Add tests

  **What to do**:
  - `initialize` response includes `loadSession: true`
  - `session/load` with known conversation → success, session created with resume info
  - `session/load` with unknown conversation → error response
  - `session/load` → `session/prompt` → resume_session_id passed to pool
  - `WorkerConfig` serialization with `resume_session_id`
  - Worker passes `resume` to `ClaudeAgentOptions`

  **File**: `pykoclaw-acp/tests/`

  **Acceptance Criteria**:
  - [ ] `uv run pytest pykoclaw-acp/tests/ -v` — all tests pass
  - [ ] `uv run pytest` — full workspace passes

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 + 2 | `feat(acp): implement session/load for resume across restarts` | `server.py`, `worker_protocol.py` | `uv run pytest pykoclaw-acp/tests/ -v` |
| 3 + 4 | `feat(acp): pass resume_session_id through worker pipeline` | `worker_pool.py`, `worker.py` | `uv run pytest pykoclaw-acp/tests/ -v` |
| 5 | `test(acp): add session/load and resume tests` | `tests/` | `uv run pytest` |

---

## Success Criteria

### Verification Commands
```bash
# All ACP tests pass
cd ~/prg/pykoclaw-dev && uv run pytest pykoclaw-acp/tests/ -v

# Full workspace regression check
uv run pytest

# Manual: restart mitto-web, verify conversation continuity
systemctl --user restart mitto-web
# Open existing conversation in Mitto UI → agent remembers prior context
# Open a different conversation → correct history (not mixed up)
```

### Final Checklist
- [ ] `initialize` advertises `loadSession: true`
- [ ] `session/load` handler implemented with DB lookup
- [ ] Worker resumes Claude Code session via `--resume`
- [ ] New conversations via `session/new` work exactly as before
- [ ] Multiple concurrent conversations resume to correct sessions
- [ ] Graceful error on unknown session (Mitto falls back to `session/new`)
- [ ] All existing tests pass unchanged
- [ ] New tests cover session/load hit/miss + resume passthrough
- [ ] Zero Mitto changes required
