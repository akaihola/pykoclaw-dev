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
| 5 | "Connection lost" after idle period | anyio cancel scope leak → spin loop | 2026-02-20 | ✅ Fixed |

---

## Issue 1: Prompt Response Ordering (2026-02-14)

**Commits:** `70c3eee`, `5f303dc`

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
Moved the JSON-RPC response to **after** `pool.send()` completes. Added
`{"stopReason": "end_turn"}` to the response body.

### Lesson
**The prompt response is the end-of-turn signal.** Never send it before
streaming is done.

---

## Issue 2: Session Resume Fails on Second Message (2026-02-14)

**Commits:** `04f5308`

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
Implemented `ClientPool` — one **long-lived** `ClaudeSDKClient` per ACP
conversation. ACP server bypasses `dispatch_to_agent()` entirely and uses
`ClientPool.send()` directly. Pool handles: create-on-first-use, per-session
lock, crash retry, idle eviction (10 min), graceful shutdown.

### Lesson
**`ClaudeSDKClient` resume only works within the same process lifetime.**
Never destroy and recreate the client between messages in a conversation.

---

## Issue 3: Shutdown Hang → Zombie Chain (2026-02-16 — 2026-02-18)

**Commits:** `7d64e3d`, `b43f2e5`, `a189cc0`

### Symptom
After a period of operation, pykoclaw processes become zombies. Mitto then
gets "broken pipe" errors on all sessions and shows "Connection lost".
Sometimes processes hang indefinitely at 100% CPU.

### Investigation (multi-day)
1. Added event-loop watchdog + faulthandler to capture tracebacks (`7d64e3d`)
2. Found: `asyncio.run()` calls `_cancel_all_tasks()` during cleanup with
   **no timeout**. If a Claude SDK subprocess won't exit, the whole process
   hangs forever.
3. Watchdog SIGKILLs the hung process → becomes zombie → Mitto doesn't
   `waitpid()` → writes to dead pipe → broken pipe → all sessions dead.

### Root cause
`asyncio.run()` has an unbounded cleanup phase that waits forever for task
cancellation. Claude SDK subprocesses don't always exit cleanly.

### Fix (iterative)
1. **`b43f2e5`**: Replaced `asyncio.run()` with manual event loop + bounded
   `_cancel_remaining_tasks()` that calls `os._exit(0)` after timeout.
2. **`a189cc0`**: Added force-exit via `os._exit()` to prevent zombie creation.

### What didn't work
- Wrapping `asyncio.run()` with a graceful shutdown wrapper — `asyncio.run()`
  runs its **own** unbounded `_cancel_all_tasks()` *after* the wrapper returns.
- SIGTERM handlers — they don't help when the event loop itself is stuck.

### Lesson
**Never use `asyncio.run()` for long-lived servers that use the Claude SDK.**
Manage the event loop manually with bounded cleanup and `os._exit()` fallback.

---

## Issue 4: Empty Replies — ResultMessage.result Dropped (2026-02-20)

**Commits:** `daa148a` (pykoclaw-acp), also fixed in pykoclaw core

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

### Fix
Forward `ResultMessage.result` as fallback text when no `TextBlock` was
streamed. Applied in **both** SDK message loops (the codebase has two
independent ones — see "Architecture" below).

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

### Fix
1. **Primary:** Wrapped `client.disconnect()` in `asyncio.shield()` in
   `_disconnect()` — prevents the cancel scope from propagating.
2. **Safety net:** `CancelledError` handler in server main loop with
   `await asyncio.sleep(0.5)` backoff and consecutive-error limit.

### What didn't work
- Catching `CancelledError` and continuing without backoff — creates spin loop.
- Suppressing `CancelledError` entirely — the exception keeps re-raising
  because the cancel scope is still active (catching it once doesn't clear it).

### Lesson
**Never call `ClaudeSDKClient.disconnect()` without `asyncio.shield()`**
when running in a task that shares the event loop with other coroutines.
anyio cancel scopes propagate across the asyncio/anyio boundary in
unexpected ways.

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
- Use `asyncio.shield()` when calling SDK disconnect/close methods
- Manage the event loop manually (`asyncio.new_event_loop()`) — not `asyncio.run()`
- Add backoff sleeps to all error-handling `continue` loops
- Keep `ClientPool` clients long-lived — don't recreate per message
- Send the prompt response LAST (after all streaming is done)
- Consume ALL text from ALL SDK message types
- Fix bugs in BOTH SDK message loops

### DON'T
- Use `asyncio.run()` for long-lived servers with SDK clients
- Call `ClaudeSDKClient.disconnect()` without `asyncio.shield()`
- Catch exceptions in a loop without backoff (creates spin loops)
- Assume `--resume` works across process restarts
- Assume `TextBlock` is the only carrier of response text
- Fix a message-handling bug in only one of the two SDK loops

---

## Open Concerns

- **Is `asyncio.shield()` sufficient long-term?** The anyio/asyncio boundary
  is fundamentally fragile. A future SDK update could introduce new leak
  vectors. Consider wrapping all SDK calls in a subprocess or thread to
  fully isolate the cancel scope.
- **ClientPool idle eviction (10 min)** triggers the disconnect code path.
  If the shield fix ever regresses, increasing `IDLE_TIMEOUT_S` or
  disabling eviction would be a stopgap.
- **Two SDK message loops** is a maintenance burden and bug duplication risk.
  Consider unifying them (though ACP's long-lived client vs WhatsApp's
  per-message client makes this non-trivial).
