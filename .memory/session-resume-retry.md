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

## Two failure modes — exit code 1 and exit code 0

The claude subprocess can fail in two distinct ways on session resume:

**Exit code 1 → `ProcessError`** — handled by `dispatch_to_agent()`:
catches the error, clears the session, and retries fresh automatically.

**Exit code 0 + empty `full_text`** — NOT caught by `dispatch_to_agent()`.
Claude starts up (~500ms), fires `SessionEnd` during initialization (no API
call made), and exits cleanly. The SDK reads EOF, gets no result, and returns
`full_text=""`. This looks identical to genuine "chose silence" but takes
only ~1–2 seconds — a real response always takes ≥ 5s.

Root cause for both: the session `.jsonl` file doesn't exist in
`~/.claude/projects/<project_hash>/<session_id>.jsonl` — either it was
never written (previous subprocess died before doing work) or the `cwd`
changed between calls.

## Channel plugins must handle the exit-code-0 case for hard mentions

`dispatch_to_agent()` cannot retry the exit-code-0 case (no exception is
raised). Callers that know a reply is mandatory (e.g. `hard_mention=True`)
must detect the empty result and retry with `fresh=True`:

```python
if hard_mention and not result.full_text:
    log.warning("Agent %s returned empty on hard-mention — retrying fresh", …)
    result = await dispatch_to_agent(…, fresh=True)
```

This is implemented in `connection.py → _dispatch_for_agent()`.

## Diagnosing which failure mode occurred

- Check `~/.claude/debug/<session_id>.txt` — if it has < 60 lines and no
  API calls, the subprocess died during startup (either mode).
- Check `~/.claude/projects/<project_hash>/<session_id>.jsonl` — if the
  file is missing, the session was never written (confirms startup failure).

[channel-dispatch.md]: channel-dispatch.md
[session-resume-system-prompt.md]: session-resume-system-prompt.md
[bananas-delivery-bug.md]: bananas-delivery-bug.md
