# ACP / Mitto Connection Issues — Investigation Log

> **READ THIS FIRST** when starting work on any Mitto or pykoclaw-acp problem.
> This is a running log of every connection issue, root cause, and fix attempt.
> The problems are recurring and subtle — understanding the full history
> prevents re-treading failed approaches.

---

## Executive Summary

Since pykoclaw-acp was created (2026-02-14), there have been **five distinct
categories** of connection failures between Mitto and pykoclaw. All present
with similar user-facing symptoms ("Connection lost", no reply, empty reply)
but have completely different root causes. The common thread is the
**claude-agent-sdk ↔ asyncio boundary** — anyio internals leak into asyncio
in surprising ways.

### Quick reference: failure modes

| # | Symptom | Root cause | Fix date | Status |
|---|---------|-----------|----------|--------|
| 1 | Empty/truncated replies | Prompt response sent before streaming done | 2026-02-14 | ✅ Fixed |
| 2 | Second message never answered | Session resume across processes impossible | 2026-02-14 | ✅ Fixed |
| 3 | Process hangs on shutdown → zombie chain | `asyncio.run()` unbounded `_cancel_all_tasks` | 2026-02-18 | ✅ Fixed |
| 4 | Empty replies (text only in ResultMessage) | `ResultMessage.result` not forwarded | 2026-02-20 | ✅ Fixed |
| 5 | "Connection lost" after idle period | anyio cancel scope leak → spin loop | 2026-02-20 | ✅ Fixed (v3) |

---

## Full Commit History (pykoclaw-acp)

Chronological list of every commit, with issue references where applicable.

| Hash | Date | Summary | Issue |
|------|------|---------|-------|
| `2a40d02` | Feb 14 | Initial ACP protocol handler (JSON-RPC 2.0) | — |
| `f9ba1e8` | Feb 14 | ACP stdio server + plugin entry point | — |
| `5f303dc` | Feb 14 | Survive errors in main loop and dispatch | #1 |
| `03b740b` | Feb 14 | Tests for dispatch error handling | #1 |
| `70c3eee` | Feb 14 | Send prompt response **after** streaming, add stopReason | #1 |
| `04f5308` | Feb 14 | Keep Claude subprocess alive across messages (ClientPool) | #2 |
| `5701abf` | Feb 14 | README with Mitto integration guide | — |
| `586e2f2` | Feb 15 | Delivery queue polling for scheduled task results | — |
| `7d64e3d` | Feb 16 | Event-loop watchdog, faulthandler, defensive fixes | #3 |
| `b7f4fc5` | Feb 16 | Docs: delivery queue polling | — |
| `7fc91f2` | Feb 16 | Playwright integration test setup | — |
| `b43f2e5` | Feb 18 | Replace `asyncio.run()` with manual loop + bounded cleanup | #3 |
| `a189cc0` | Feb 18 | Force-exit on shutdown via `os._exit()` | #3 |
| `9cc2597` | Feb 18 | Update tests to mock `pool.send` (not stale dispatch) | — |
| `3f973df` | Feb 18 | `--healthcheck` smoke test for deploy verification | — |
| `be3e7f4` | Feb 18 | Structured diagnostic logging throughout lifecycle | — |
| `4e668d8` | Feb 18 | File-based logging (survives Mitto stderr capture) | — |
| `0914dd2` | Feb 18 | Merge `feature/acp-diagnostics` | — |
| `f8354dc` | Feb 19 | Integration tests with mock LLM + test client | — |
| `fa6ead8` | Feb 19 | E2E tests over subprocess stdio | — |
| `daa148a` | Feb 20 | Forward `ResultMessage.result` as fallback text | #4 |
| `79bd952` | Feb 20 | Shield disconnect from anyio CancelledError leak | #5 (v1, insufficient) |
| `55124d6` | Feb 20 | Isolate disconnect in separate task | #5 (v2, insufficient) |
| `adf208e` | Feb 21 | Replace disconnect() with subprocess kill | #5 (v3, **actual fix**) |
| `aeb04f4` | Feb 21 | Architecture fragility backlog item | — |

### Related commits in other repos

| Repo | Hash | Summary | Issue |
|------|------|---------|-------|
| pykoclaw (core) | `fbe257c` | Forward `ResultMessage.result` in `query_agent()` | #4 |
| pykoclaw-messaging | `6f5c414` | Use `ResultMessage.result` as fallback in `dispatch.py` | #4 |

---

## Issue 1: Prompt Response Ordering (2026-02-14)

**Commits:** `5f303dc` (error survival), `70c3eee` (response ordering fix)

### Symptom
First messages to Mitto sessions returned empty or truncated replies.

### Investigation
Mitto's `acp.Connection.Prompt()` blocks until the JSON-RPC response with
matching `id` arrives. Pykoclaw was sending the response **immediately**
(with empty `{}` body), then streaming `session/update` notifications
afterward. Mitto returned from `Prompt()` before any content arrived.

### Root cause
Wrong ordering of ACP protocol messages. The protocol requires:
1. Client sends `session/prompt` request
2. Agent sends `session/update` notifications (streaming chunks)
3. Agent sends the `session/prompt` **response** with `{"stopReason": "end_turn"}`

Pykoclaw had step 3 before step 2.

### Fix
- `5f303dc` — added error handling so main loop and dispatch survive crashes
- `70c3eee` — moved JSON-RPC response to **after** streaming completes,
  added `{"stopReason": "end_turn"}` to body

### Lesson
**The prompt response is the end-of-turn signal.** Never send it before
streaming is done.

---

## Issue 2: Session Resume Fails on Second Message (2026-02-14)

**Commits:** `04f5308` (ClientPool implementation)

### Symptom
First message in any Mitto conversation works. Second message gets no response.
Claude CLI exits with code 1: `"No conversation found with session ID"`.

### Investigation
`dispatch_to_agent()` → `query_agent()` creates a **new** `ClaudeSDKClient`
(= new `claude` subprocess) for every call. First call creates a session and
persists the session ID. Second call passes `resume=<session_id>`, but the
CLI can't find it — the JSONL file only has a `dequeue` operation, not the
full conversation.

### Root cause
The Claude Agent SDK doesn't persist sessions in a way compatible with
`--resume` across separate subprocess invocations. Session state lives in
the process, not on disk.

### Fix
- `04f5308` — implemented `ClientPool`: one **long-lived** `ClaudeSDKClient`
  per ACP conversation. ACP server bypasses `dispatch_to_agent()` entirely
  and uses `ClientPool.send()` directly. Pool handles: create-on-first-use,
  per-session lock, crash retry, idle eviction (10 min), graceful shutdown.

### Lesson
**`ClaudeSDKClient` resume only works within the same process lifetime.**
Never destroy and recreate the client between messages in a conversation.

---

## Issue 3: Shutdown Hang → Zombie Chain (2026-02-16 — 2026-02-18)

**Commits:** `7d64e3d` (watchdog + diagnostics), `b43f2e5` (bounded shutdown),
`a189cc0` (force-exit), `be3e7f4` (diagnostic logging), `4e668d8` (file logging)

### Symptom
After a period of operation, pykoclaw processes become zombies. Mitto then
gets "broken pipe" errors on all sessions and shows "Connection lost".
Sometimes processes hang indefinitely at 100% CPU.

### Investigation (multi-day)
1. `7d64e3d` — added event-loop watchdog + faulthandler to capture tracebacks
2. Found: `asyncio.run()` calls `_cancel_all_tasks()` during cleanup with
   **no timeout**. If a Claude SDK subprocess won't exit, the whole process
   hangs forever.
3. Watchdog SIGKILLs the hung process → becomes zombie → Mitto doesn't
   `waitpid()` → writes to dead pipe → broken pipe → all sessions dead.
4. `be3e7f4`, `4e668d8` — added structured + file-based logging to capture
   diagnostics that were lost when Mitto captured stderr

### Root cause
`asyncio.run()` has an unbounded cleanup phase that waits forever for task
cancellation. Claude SDK subprocesses don't always exit cleanly.

### Fix (iterative)
1. `b43f2e5` — replaced `asyncio.run()` with manual event loop + bounded
   `_cancel_remaining_tasks()` that calls `os._exit(0)` after timeout
2. `a189cc0` — added force-exit via `os._exit()` to prevent zombie creation

### What didn't work
- Wrapping `asyncio.run()` with a graceful shutdown wrapper — `asyncio.run()`
  runs its **own** unbounded `_cancel_all_tasks()` *after* the wrapper returns.
- SIGTERM handlers — they don't help when the event loop itself is stuck.

### Lesson
**Never use `asyncio.run()` for long-lived servers that use the Claude SDK.**
Manage the event loop manually with bounded cleanup and `os._exit()` fallback.

---

## Issue 4: Empty Replies — ResultMessage.result Dropped (2026-02-20)

**Commits:** `daa148a` (ACP path), `fbe257c` (core path), `6f5c414` (messaging path)

### Symptom
Agent responds (visible in Claude debug logs) but Mitto shows empty reply.

### Investigation
During multi-turn tool-use sessions, sometimes the final text only appears
in `ResultMessage.result` and is NOT re-emitted as a `TextBlock`. Both
`ClientPool._query()` (ACP path) and `query_agent()` (WhatsApp path) only
consumed `TextBlock` content, silently dropping `ResultMessage.result`.

### Root cause
Incomplete SDK message consumption. The `ResultMessage` carries the full
response text but was treated as metadata-only.

### Fix (three repos)
- `daa148a` (pykoclaw-acp) — forward `ResultMessage.result` in `ClientPool._query()`
- `fbe257c` (pykoclaw core) — forward `ResultMessage.result` in `query_agent()`
- `6f5c414` (pykoclaw-messaging) — use result text as fallback in `dispatch.py`

### Lesson
**Always consume ALL text fields from SDK message types.** There are two
independent SDK message loops that must be kept in sync — bugs must be
fixed in both:
1. `pykoclaw/src/pykoclaw/agent_core.py` → `query_agent()` (WhatsApp, scheduler)
2. `pykoclaw-acp/src/pykoclaw_acp/client_pool.py` → `ClientPool._query()` (Mitto)

---

## Issue 5: anyio Cancel Scope Leak → Spin Loop (2026-02-20)

**Commits:** `79bd952`

### Symptom
User gets "Connection lost and could not reconnect" in Mitto. Happens after
a period of idle time (~10 minutes). The ACP process becomes unresponsive
then gets killed and restarted, but the in-flight conversation is lost.

### Investigation
`journalctl` showed **45,778** `CancelledError` warnings logged in ~8 minutes
(22:28:23 → 22:36:29), all from the same PID. The error spam started
immediately after `_sweep_loop` evicted an idle client.

Timeline (PID 2982970):
1. 22:02:23 — ACP server starts, creates pooled client
2. 22:28:23 — `_sweep_loop` evicts idle client (10 min timeout)
3. `_disconnect()` → `client.disconnect()` → `Query.close()` →
   `self._tg.cancel_scope.cancel()`
4. anyio cancel scope **leaks** CancelledError into the asyncio event loop
5. The `reader.readline()` in the main server loop gets cancelled
6. Exception handler catches it and continues — but **with no backoff**
7. Tight spin loop: catch → continue → readline → cancelled → catch → ...
8. 45k+ warnings, 100% CPU, can't read stdin
9. 22:36:29 — Mitto kills the process; 22:36:58 — new process spawned

### Root cause
`ClaudeSDKClient.disconnect()` calls `Query.close()` which does
`self._tg.cancel_scope.cancel()`. This is an **anyio** operation that leaks
a `CancelledError` into the asyncio event loop, affecting unrelated awaits
in the same task.

An earlier fix attempt had added a `CancelledError` catch in the main loop,
but without any backoff sleep — turning the leak into a CPU-pegging spin
loop instead of a crash.

### Fix attempts

**v1 — `79bd952` (2026-02-20, insufficient):**
Wrapped `client.disconnect()` in `asyncio.shield()` + added backoff sleep
in the `CancelledError` handler. **Result:** still crashed. `asyncio.shield()`
only protects against *outer* cancellation — doesn't isolate *inner* anyio
cancel scope effects.

**v2 — `55124d6` (2026-02-20, insufficient):**
Ran `disconnect()` in a completely separate `asyncio.create_task()` with
`asyncio.shield()`. Added `except BaseException` in `_sweep_loop`.
**Result:** still crashed. Anyio cancel scopes target the *host task* by
identity (whichever task called `connect()`), not the task currently
running `disconnect()`.

**v3 — `adf208e` (2026-02-21, actual fix):**
Never call `client.disconnect()` at all. New `_kill_client()` function
terminates the subprocess directly (SIGTERM → wait → SIGKILL) and nulls
out references. Completely avoids anyio cancel scope machinery.

### What didn't work
- `asyncio.shield()` — only protects against outer cancellation, not inner
  anyio cancel scope effects
- `asyncio.create_task()` — anyio targets the host task by identity, not
  the current task
- `await asyncio.sleep(0.5)` inside `except CancelledError` — the sleep
  itself gets cancelled, escaping the handler and killing the loop
- Catching `CancelledError` and continuing without backoff — creates spin loop

### Root cause (proven with real SDK in tests)
`test_kill_client.py::test_sdk_disconnect_DOES_leak_cancelled_error` proves
that `asyncio.shield(client.disconnect())` raises `CancelledError` in the
calling task. The anyio cancel scope inside `Query.close()` targets the
asyncio Task that called `connect()` **by identity**, bypassing all asyncio
isolation mechanisms.

### Lesson
**Never call `ClaudeSDKClient.disconnect()`.** The anyio/asyncio impedance
mismatch makes it impossible to call safely from asyncio code. Kill the
subprocess directly instead. See
`pykoclaw-acp/backlog/001-acp-architecture-fragility.md` for the long-term
architecture recommendation (process-isolated workers).

---

## Architecture Notes

### Data flow
```
User → Mitto web UI → Mitto Go process
  → pykoclaw-acp subprocess (JSON-RPC over stdio)
    → ClientPool → ClaudeSDKClient → claude CLI subprocess
```

### Two independent SDK message loops
**This is critical.** Bugs in message handling must be fixed in BOTH:

1. `pykoclaw/src/pykoclaw/agent_core.py` → `query_agent()`
   Used by: WhatsApp, scheduler
2. `pykoclaw-acp/src/pykoclaw_acp/client_pool.py` → `ClientPool._query()`
   Used by: Mitto/ACP

### The anyio/asyncio boundary
The claude-agent-sdk uses **anyio** internally (task groups, cancel scopes,
memory object streams). Pykoclaw uses **asyncio**. This boundary is the
source of most subtle bugs:

- anyio cancel scopes leak `CancelledError` into asyncio tasks
- anyio task groups don't always clean up within asyncio's expectations
- `asyncio.run()` vs anyio task group cleanup interact badly

### Key diagnostic locations
| What | Where |
|------|-------|
| Mitto systemd logs | `journalctl --user -u mitto-web` |
| ACP file logs | `~/.local/state/pykoclaw/acp-<pid>.log` |
| Faulthandler traces | `~/.local/state/pykoclaw/faulthandler-<pid>.txt` |
| Mitto session events | `~/.local/share/mitto/sessions/<id>/events.jsonl` |
| Claude CLI debug | `~/.claude/debug/<session-id>.txt` |
| Pykoclaw DB | `~/.local/share/pykoclaw/pykoclaw.db` |

---

## Patterns & Anti-patterns

### DO
- Use `_kill_client()` to tear down SDK clients — never `client.disconnect()`
- Manage the event loop manually (`asyncio.new_event_loop()`) — not `asyncio.run()`
- Add backoff sleeps to all error-handling `continue` loops
- Keep `ClientPool` clients long-lived — don't recreate per message
- Send the prompt response LAST (after all streaming is done)
- Consume ALL text from ALL SDK message types
- Fix bugs in BOTH SDK message loops

### DON'T
- Use `asyncio.run()` for long-lived servers with SDK clients
- Call `ClaudeSDKClient.disconnect()` — ever (use `_kill_client()` instead)
- Catch exceptions in a loop without backoff (creates spin loops)
- Assume `--resume` works across process restarts
- Assume `TextBlock` is the only carrier of response text
- Fix a message-handling bug in only one of the two SDK loops

---

## Open Concerns

- **`_kill_client()` is a workaround, not a fix.** It bypasses SDK cleanup
  entirely. If the SDK ever requires graceful shutdown for correctness
  (e.g. flushing session state), this will break. The proper fix is
  process-isolated workers — see `pykoclaw-acp/backlog/001-acp-architecture-fragility.md`.
- **Two SDK message loops** is a maintenance burden and bug duplication risk.
  Consider unifying them (though ACP's long-lived client vs WhatsApp's
  per-message client makes this non-trivial).
- **The `CancelledError` safety net in the server main loop** is still present
  as defense-in-depth. With `_kill_client()`, it should never trigger. If it
  does, that means a new cancel scope leak vector has appeared.

## Resolved Concerns

- ~~**Is `asyncio.shield()` sufficient long-term?**~~ No. Proven insufficient.
  Replaced with `_kill_client()` subprocess termination (2026-02-21).
