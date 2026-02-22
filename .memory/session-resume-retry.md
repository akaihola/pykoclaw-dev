# Session Resume Retry Pattern

**Tags:** claude-sdk, dispatch, scheduler, gotcha
**Related:** [channel-dispatch.md], [session-resume-system-prompt.md], [bananas-delivery-bug.md]

`claude_agent_sdk` subprocess CLI fails with `ProcessError` (exit code 1)
when resuming a session whose state is corrupt or missing on disk. This
happens after restarts, crypto store resets, or the first call saving an
empty session directory.

## Where the retry lives

The retry-on-`ProcessError` logic is built into **both** message paths:

1. **`dispatch_to_agent()`** in `pykoclaw-messaging` — handles live
   channel messages (WhatsApp, Matrix, ACP).
2. **`run_task()`** in `pykoclaw/scheduler.py` — handles scheduled tasks.

Both follow the same pattern: catch `ProcessError` when `resume_session_id`
is set, clear the session via `upsert_conversation(db, name, None, cwd)`,
and retry fresh. If already fresh (`resume_session_id is None`), the error
propagates.

## Stale prompt hash detection

Both paths also check `system_prompt_hash` stored in the conversations
table. If the hash of the current system prompt differs from the stored
hash, the session is discarded before even attempting resume (code deploys
that change the prompt would otherwise resume into a stale context).

The hash is computed by `prompt_hash()` in `pykoclaw.agent_core` (public
API — not prefixed with underscore).

## Channel plugins no longer need retry logic

Since the retry is in `dispatch_to_agent()` itself, individual channel
plugins (WhatsApp, Matrix, etc.) do **not** need their own try/except
around dispatch calls for this failure mode.

[channel-dispatch.md]: channel-dispatch.md
[session-resume-system-prompt.md]: session-resume-system-prompt.md
[bananas-delivery-bug.md]: bananas-delivery-bug.md
