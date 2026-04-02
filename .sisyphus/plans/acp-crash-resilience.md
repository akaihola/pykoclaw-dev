# ACP Server Crash Resilience

## Status: Done

## Completed: 2026-02-14

## TL;DR

> **Quick Summary**: Fix the ACP server so it doesn't die when `dispatch_to_agent()` raises an exception. Currently, any error during agent processing kills the entire server process, showing users "Lost connection to the AI agent." Three surgical changes in `server.py` plus new tests.
>
> **Deliverables**:
> - `server.py`: Exception handling around `dispatch_to_agent()` + error notification to Mitto
> - `server.py`: Main loop `break` → `continue` so transient errors don't kill server
> - `test_server.py`: 3–4 new tests covering error handling behavior
>
> **Estimated Effort**: Quick
> **Parallel Execution**: NO — sequential (single file, ~30 lines of prod code)
> **Critical Path**: Task 1 → Task 2 → Task 3

---

## Context

### Original Request

User experienced "Lost connection to the AI agent" in a Mitto conversation with the Tyko agent on Feb 14, 2026. Session started at 14:58, last activity at 19:25. Investigation revealed the ACP server process crashed (became a zombie) when processing the prompt "What does your AGENTS.md tell you?"

### Investigation Findings

**Timeline from `events.jsonl`:**

| Time     | Event                                  | Seq |
|----------|----------------------------------------|-----|
| 14:58:22 | Session created                        | 1   |
| 19:10:10 | User: "Who are you?"                   | 2   |
| 19:10:20 | Agent responds (4 chunks)              | 3–6 |
| 19:10:22 | Agent: "What can I help you with?"     | 7   |
| 19:10:59 | User: "What does your AGENTS.md tell?" | 8   |
| —        | **No agent response (crash)**          | —   |
| 19:14:26 | User: "So?"                            | 9   |
| —        | **No response — "Lost connection"**    | —   |

**Process evidence:**
```
PID 1364428  Z+  14:58  [pykoclaw] <defunct>  ← First Tyko (crashed)
PID 1395968  Z+  19:10  [pykoclaw] <defunct>  ← Second Tyko (also crashed)
```

**Root cause:** `dispatch_to_agent()` raised an exception during agent processing. Because there is zero error handling around this call, the exception propagated through `_dispatch()` into the main `run()` loop, where the catch-all on line 61–63 does `break` — killing the server.

### Three Bugs Identified

1. **No error handling in `_handle_session_prompt`** (`server.py:160-167`): The `dispatch_to_agent()` call has zero exception protection. Any error kills the server.

2. **Main loop `break` instead of `continue`** (`server.py:61-63`): The catch-all exception handler exits the server loop permanently instead of recovering.

3. **No error notification to Mitto**: After the ack (line 144), if dispatch fails, Mitto gets silence — no error response, no `session/update`. The pipe just goes dead.

### Metis Review

**Identified Gaps (addressed):**
- Metis corrected the assumption about missing tests — tests DO exist in `test_server.py` (7 tests) and `test_protocol.py` (10 tests) with `_collect_writes()` + `AsyncMock` patterns ready to extend.
- Metis identified the ack-then-silence race: line 144 sends an ack BEFORE dispatch. If dispatch fails, Mitto already received "ok" but never gets content or an error.
- Metis flagged that `asyncio.CancelledError` is a `BaseException` in Python 3.12, so `except Exception` correctly does NOT catch it — clean shutdown is preserved.
- Metis confirmed `_write()` already handles broken stdout (lines 170-174), so error notifications during pipe failures are safe.

---

## Work Objectives

### Core Objective

Make the ACP server survive `dispatch_to_agent()` failures gracefully — log the error, notify Mitto, and continue serving subsequent messages.

### Concrete Deliverables

- `pykoclaw-acp/src/pykoclaw_acp/server.py` — 2 changes (~15 lines added)
- `pykoclaw-acp/tests/test_server.py` — 3–4 new test functions (~60 lines)

### Definition of Done

- [x] Existing 17+ tests still pass: `uv run pytest pykoclaw-acp/tests/ -v`
- [x] New error-handling tests pass: `uv run pytest pykoclaw-acp/tests/test_server.py -v -k "error"`
- [x] Full workspace tests pass: `uv run pytest`

### Must Have

- `dispatch_to_agent()` wrapped in `try/except Exception`
- Error notification sent to Mitto via `session/update` when dispatch fails
- Main loop continues after transient errors (`continue`, not `break`)
- Full exception traceback logged via `log.exception()`
- All existing tests pass unchanged

### Must NOT Have (Guardrails)

- MUST NOT add retry/backoff logic for failed dispatch
- MUST NOT add file-based log handlers (separate concern)
- MUST NOT modify `protocol.py` beyond trivially needed changes
- MUST NOT add keepalive/heartbeat mechanism (separate feature)
- MUST NOT touch `dispatch.py` or `agent_core.py` — errors handled at call site
- MUST NOT touch `pykoclaw-whatsapp` (already handles errors correctly)
- MUST NOT create custom exception classes (YAGNI)
- MUST NOT add signal handlers or graceful shutdown logic
- MUST NOT catch `BaseException` — only `Exception` (preserve `CancelledError`/`SystemExit`)

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL verification is executed by the agent using commands and tools.

### Test Decision

- **Infrastructure exists**: YES — pytest + pytest-asyncio
- **Automated tests**: YES (tests-after — adding tests for new error handling)
- **Framework**: pytest (via `uv run pytest`)

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

See per-task scenarios below. Primary verification is running the existing and new test suite.

---

## Execution Strategy

### Sequential Execution

All three tasks modify the same file (`server.py`) and its test file. They must be sequential.

```
Task 1: Fix main loop break → continue
  ↓
Task 2: Add error handling around dispatch_to_agent()
  ↓
Task 3: Add tests for error handling behavior
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1    | None       | 3      | None                |
| 2    | None       | 3      | None (same file)    |
| 3    | 1, 2       | None   | None (final)        |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agent |
|------|-------|-------------------|
| 1    | 1, 2, 3 | Single `category="quick"` — all three are small changes in one file |

---

## TODOs

- [x] 1. Fix main loop to continue on errors instead of dying

  **What to do**:
  - In `server.py` line 63, change `break` to `continue`
  - This is a one-word change
  - The catch-all `except Exception` on line 61 currently kills the server on ANY error during message processing. After this fix, the server logs the error and moves on to the next message.

  **Must NOT do**:
  - Do NOT remove the `log.exception()` call — it's useful for debugging
  - Do NOT change the exception type (keep `Exception`, not `BaseException`)
  - Do NOT add retry logic

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single-word change in one file
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (same file as Task 2)
  - **Blocks**: Task 3
  - **Blocked By**: None

  **References**:

  **Pattern References:**
  - `pykoclaw-acp/src/pykoclaw_acp/server.py:39-64` — The main `run()` loop with the `while self._running` loop. Line 61–63 is the catch-all exception handler that currently does `break`. Change `break` to `continue`.

  **Acceptance Criteria**:

  - [ ] Line 63 of `server.py` reads `continue` instead of `break`
  - [ ] `uv run pytest pykoclaw-acp/tests/ -v` — all existing tests still pass

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Existing tests still pass after break→continue change
    Tool: Bash
    Preconditions: Working directory is /home/agent/prg/pykoclaw-dev
    Steps:
      1. uv run pytest pykoclaw-acp/tests/ -v
      2. Assert: exit code 0
      3. Assert: all 17+ tests pass, 0 failures
    Expected Result: All tests pass unchanged
    Evidence: Terminal output captured
  ```

  **Commit**: YES (groups with Task 2)
  - Message: `fix(acp): survive errors in main loop and dispatch`
  - Files: `pykoclaw-acp/src/pykoclaw_acp/server.py`
  - Pre-commit: `uv run pytest pykoclaw-acp/tests/ -v`

---

- [x] 2. Add error handling around `dispatch_to_agent()` with error notification

  **What to do**:
  - Wrap the `dispatch_to_agent()` call (lines 160–167) in a `try/except Exception` block
  - In the `except` block:
    1. Log the full exception: `log.exception("Agent dispatch failed for session %s", session_id)`
    2. Send an error notification to Mitto via `session/update` so the client shows an error instead of "Lost connection"
  - The error notification should use the existing `format_notification()` method with a `session/update` containing an error-typed update

  **Exact change — replace lines 160–167:**
  ```python
  # BEFORE (lines 160-167):
  await dispatch_to_agent(
      prompt=content,
      channel_prefix="acp",
      channel_id=session_id[:8],
      db=self._db,
      data_dir=self._data_dir,
      on_text=_send_chunk,
  )

  # AFTER:
  try:
      await dispatch_to_agent(
          prompt=content,
          channel_prefix="acp",
          channel_id=session_id[:8],
          db=self._db,
          data_dir=self._data_dir,
          on_text=_send_chunk,
      )
  except Exception:
      log.exception("Agent dispatch failed for session %s", session_id)
      self._write(
          self._protocol.format_notification(
              "session/update",
              {
                  "sessionId": session_id,
                  "update": {
                      "sessionUpdate": "error",
                      "error": "Agent processing failed. Please try again.",
                  },
              },
          )
      )
  ```

  **Must NOT do**:
  - Do NOT catch `BaseException` — only `Exception`
  - Do NOT add retry logic
  - Do NOT modify `dispatch.py` or `agent_core.py`
  - Do NOT include Python tracebacks in the error message sent to Mitto (they're logged server-side via `log.exception()`)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: ~15 lines added to a single function in one file
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (same file as Task 1)
  - **Blocks**: Task 3
  - **Blocked By**: None (can be done alongside Task 1 since they're different locations)

  **References**:

  **Pattern References:**
  - `pykoclaw-acp/src/pykoclaw_acp/server.py:112-167` — The `_handle_session_prompt()` method. Lines 143–144 send the ack BEFORE dispatch starts. Lines 146–158 define the `_send_chunk` callback. Lines 160–167 are the unprotected `dispatch_to_agent()` call to wrap.
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:200-222` — WhatsApp's pattern: `dispatch_to_agent()` wrapped in `try/except Exception: log.exception(...)`. Follow this pattern but also send an error notification since ACP has a notification channel.

  **API/Type References:**
  - `pykoclaw-acp/src/pykoclaw_acp/protocol.py:51-52` — `format_notification(method, params)` — use this to send the error notification
  - `pykoclaw-acp/src/pykoclaw_acp/protocol.py:12-20` — `JsonRpcError` codes — `INTERNAL_ERROR = -32603` and `SESSION_ERROR = -32001` exist but are not needed since we're sending a notification, not an error response

  **Acceptance Criteria**:

  - [ ] `dispatch_to_agent()` call is wrapped in `try/except Exception`
  - [ ] Exception block logs via `log.exception()`
  - [ ] Exception block sends `session/update` notification with error info
  - [ ] `uv run pytest pykoclaw-acp/tests/ -v` — all existing tests still pass

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Existing tests still pass after adding error handling
    Tool: Bash
    Preconditions: Working directory is /home/agent/prg/pykoclaw-dev
    Steps:
      1. uv run pytest pykoclaw-acp/tests/ -v
      2. Assert: exit code 0
      3. Assert: all 17+ tests pass, 0 failures
    Expected Result: All tests pass unchanged
    Evidence: Terminal output captured
  ```

  **Commit**: YES (groups with Task 1)
  - Message: `fix(acp): survive errors in main loop and dispatch`
  - Files: `pykoclaw-acp/src/pykoclaw_acp/server.py`
  - Pre-commit: `uv run pytest pykoclaw-acp/tests/ -v`

---

- [x] 3. Add tests for error handling behavior

  **What to do**:
  - Add 3–4 new test functions to `test_server.py` using the existing `_collect_writes()` + `AsyncMock` pattern:

  **Test 1: `test_session_prompt_dispatch_error_sends_notification`**
  - Create a session via `session/new`
  - Mock `dispatch_to_agent` to raise `RuntimeError("API timeout")`
  - Send a `session/prompt` message
  - Assert: ack is written (the immediate `format_response(msg_id, {})`)
  - Assert: error notification is written after the ack
  - Assert: error notification is a `session/update` with `"sessionUpdate": "error"` and an `"error"` string
  - Assert: error notification includes the correct `sessionId`

  **Test 2: `test_session_prompt_dispatch_error_server_survives`**
  - Create a session via `session/new`
  - Mock `dispatch_to_agent` to raise `RuntimeError("boom")`
  - Send a `session/prompt` — expect ack + error notification
  - Then send `initialize` — expect a valid response
  - This proves the server didn't die after the dispatch error

  **Test 3: `test_main_loop_continues_after_dispatch_error`**
  - This tests the `run()` loop behavior more directly
  - Mock `_dispatch` to raise once, then work normally on second call
  - Feed two lines to stdin
  - Assert: both messages are processed (second one succeeds)
  - This verifies the `break` → `continue` fix

  **Test 4 (optional): `test_dispatch_error_does_not_catch_cancelled_error`**
  - Mock `dispatch_to_agent` to raise `asyncio.CancelledError`
  - Assert: `CancelledError` propagates (is NOT caught by the `except Exception`)
  - This ensures clean shutdown still works

  **Must NOT do**:
  - Do NOT test internal implementation details beyond the JSON-RPC contract
  - Do NOT add integration tests requiring a real Claude API connection
  - Do NOT modify existing tests

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Adding test functions using existing patterns and fixtures
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (depends on Tasks 1 and 2)
  - **Blocks**: None (final task)
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References:**
  - `pykoclaw-acp/tests/test_server.py:37-47` — `_collect_writes()` helper — captures all JSON-RPC messages written by the server. Use this in all new tests.
  - `pykoclaw-acp/tests/test_server.py:122-157` — `test_session_prompt_streams_via_dispatch` — the existing pattern for testing `session/prompt` with a mocked `dispatch_to_agent`. Follow this structure exactly: create session first, then patch dispatch, then send prompt, then assert writes.
  - `pykoclaw-acp/tests/test_server.py:17-34` — Fixtures: `tmp_db` creates an in-memory SQLite with the conversations table, `server` creates an `AcpServer` instance. Reuse these fixtures.
  - `pykoclaw-acp/tests/test_server.py:50-59` — `test_initialize` — example of a simple dispatch test. Use this pattern for the "server survives after error" test.

  **API/Type References:**
  - `pykoclaw-acp/src/pykoclaw_acp/protocol.py:12-20` — `JsonRpcError` — import this in tests (already imported)
  - `unittest.mock.AsyncMock` — used throughout existing tests for mocking `dispatch_to_agent`

  **Acceptance Criteria**:

  - [ ] 3–4 new test functions added to `test_server.py`
  - [ ] `uv run pytest pykoclaw-acp/tests/test_server.py -v -k "error"` — new tests pass
  - [ ] `uv run pytest pykoclaw-acp/tests/ -v` — ALL tests pass (existing + new)
  - [ ] `uv run pytest` — full workspace tests pass

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: New error-handling tests pass
    Tool: Bash
    Preconditions: Working directory is /home/agent/prg/pykoclaw-dev, Tasks 1 and 2 complete
    Steps:
      1. uv run pytest pykoclaw-acp/tests/test_server.py -v -k "error"
      2. Assert: exit code 0
      3. Assert: 3+ tests pass matching "error"
    Expected Result: All error tests pass
    Evidence: Terminal output captured

  Scenario: Full ACP test suite passes
    Tool: Bash
    Preconditions: Working directory is /home/agent/prg/pykoclaw-dev
    Steps:
      1. uv run pytest pykoclaw-acp/tests/ -v
      2. Assert: exit code 0
      3. Assert: 20+ tests pass (17 existing + 3+ new), 0 failures
    Expected Result: All tests pass
    Evidence: Terminal output captured

  Scenario: Full workspace tests pass (regression check)
    Tool: Bash
    Preconditions: Working directory is /home/agent/prg/pykoclaw-dev
    Steps:
      1. uv run pytest
      2. Assert: exit code 0
      3. Assert: 0 failures
    Expected Result: No regressions across the entire workspace
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `test(acp): add error handling tests for dispatch failures`
  - Files: `pykoclaw-acp/tests/test_server.py`
  - Pre-commit: `uv run pytest pykoclaw-acp/tests/ -v`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 + 2 | `fix(acp): survive errors in main loop and dispatch` | `pykoclaw-acp/src/pykoclaw_acp/server.py` | `uv run pytest pykoclaw-acp/tests/ -v` |
| 3 | `test(acp): add error handling tests for dispatch failures` | `pykoclaw-acp/tests/test_server.py` | `uv run pytest pykoclaw-acp/tests/ -v` |

---

## Success Criteria

### Verification Commands
```bash
# All ACP tests pass (existing + new)
uv run pytest pykoclaw-acp/tests/ -v
# Expected: 20+ tests pass, 0 failures

# New error tests specifically
uv run pytest pykoclaw-acp/tests/test_server.py -v -k "error"
# Expected: 3+ tests pass

# Full workspace regression check
uv run pytest
# Expected: all tests pass, 0 failures
```

### Final Checklist
- [x] `dispatch_to_agent()` wrapped in try/except — server survives failures
- [x] Error notification sent to Mitto via `session/update` — no more silent pipe death
- [x] Main loop uses `continue` not `break` — transient errors don't kill server
- [x] 3+ new tests cover error handling behavior
- [x] All existing tests pass unchanged
- [x] No retry logic, no file logging, no signal handlers added (guardrails)
