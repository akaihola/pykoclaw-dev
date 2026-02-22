# Session Resume Retry Pattern

**Tags:** claude-sdk, dispatch, gotcha, channel-plugins
**Related:** [channel-dispatch.md], [debugging-workflow.md]

`claude_agent_sdk` subprocess CLI fails with `ProcessError` (exit code 1)
when resuming a session whose state is corrupt or missing on disk. This
happens after restarts, crypto store resets, or the first call saving an
empty session directory.

**Fix pattern (in channel connection's agent trigger):**

```python
try:
    result = await dispatch_to_agent(...)
except Exception:
    log.warning("dispatch failed, retrying without session resume")
    upsert_conversation(db, conv_name, "", str(data_dir))
    result = await dispatch_to_agent(...)
```

Clear the session_id via `upsert_conversation` so the retry starts fresh.

**Scope:** Affects ALL channel plugins using `dispatch_to_agent()`. Consider
moving the retry logic into `pykoclaw-messaging`'s `dispatch_to_agent()`
itself to avoid duplicating it in every plugin.

[channel-dispatch.md]: channel-dispatch.md
[debugging-workflow.md]: debugging-workflow.md
