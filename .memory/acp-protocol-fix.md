# ACP Prompt Response Protocol Fix

**Tags:** acp, protocol, bugfix, mitto, claude-sdk
**Related:** [mitto-setup.md], [channel-dispatch.md]

## Bug 1: Response ordering (2026-02-14)

Pykoclaw ACP server sent the `session/prompt` JSON-RPC response **immediately**
with an empty `{}` body, then streamed `session/update` notifications afterward.

### Root cause

The ACP protocol requires this order:

1. Client sends `session/prompt` request
2. Agent sends `session/update` notifications (streaming chunks)
3. Agent sends the `session/prompt` **response** with `{"stopReason": "end_turn"}`

Pykoclaw had step 3 before step 2 (and with no `stopReason`). Mitto's
`Prompt()` call blocks until the response arrives — so it returned immediately,
marked the turn complete, and discarded most of the streamed chunks.

### Fix

In `pykoclaw-acp/src/pykoclaw_acp/server.py`, moved the response to **after**
`dispatch_to_agent()` completes and added `{"stopReason": "end_turn"}`.

## Bug 2: Session resume fails on second prompt (2026-02-14)

After fixing bug 1, the first prompt works but the **second prompt always
fails** with `"No conversation found with session ID"`.

### Root cause

`query_agent()` creates a new `ClaudeSDKClient` (= new `claude` subprocess)
for every call. The first call creates a session and persists the session ID
in pykoclaw's DB. The second call passes `resume=<session_id>`, but the
Claude CLI cannot find the session because the JSONL file only contains a
`dequeue` operation — no actual conversation data.

The Claude Agent SDK doesn't persist sessions in a way that's compatible with
`--resume` across separate subprocess invocations. Session state lives in the
process, not on disk.

### Symptom

Second (and subsequent) messages to any ACP conversation get no response.
The Claude CLI exits with code 1, pykoclaw sends an error notification +
`stopReason`, but Mitto doesn't display the error to the user.

### Fix (2026-02-14)

Implemented `ClientPool` in `pykoclaw-acp/src/pykoclaw_acp/client_pool.py`.
One long-lived `ClaudeSDKClient` per conversation, managed by the ACP server.
Core (`agent_core.py`, `dispatch.py`) unchanged — ACP server bypasses
`dispatch_to_agent()` and talks to `ClientPool.send()` directly.

The pool handles: create-on-first-use, per-session lock, crash retry,
idle eviction (10 min), graceful shutdown.

## Key takeaways

- The `session/prompt` response is the **end-of-turn signal** in ACP. Never
  send it before streaming is done.
- `ClaudeSDKClient` resume only works within the **same process lifetime**.
  Cross-process resume via `--resume` flag requires proper JSONL persistence,
  which the Agent SDK doesn't provide.

[mitto-setup.md]: mitto-setup.md
[channel-dispatch.md]: channel-dispatch.md
