# Debugging workflow lessons

**Tags:** debugging, workflow, gotcha, acp, whatsapp
**Related:** [channel-dispatch.md], [result-message-fallback.md]

## Ask which channel FIRST

Before touching code, always ask: **which channel is this on?** (Mitto/ACP,
WhatsApp, chat REPL, scheduler). The code paths diverge early:

- **Mitto/ACP**: `AcpServer` → `ClientPool._query()` — has its **own SDK
  message loop**, completely independent of `query_agent()` / `dispatch_to_agent()`.
- **WhatsApp**: `WhatsAppConnection` → `dispatch_to_agent()` → `query_agent()`.
- **Scheduler**: `run_task()` → `query_agent()`.

Fixing the wrong path wastes time and doesn't help the user.

## Two SDK message loops

There are **two independent loops** that consume `ClaudeSDKClient.receive_response()`:

1. `pykoclaw/src/pykoclaw/agent_core.py` → `query_agent()` — used by WhatsApp
   and scheduler.
2. `pykoclaw-acp/src/pykoclaw_acp/client_pool.py` → `ClientPool._query()` —
   used by Mitto/ACP.

Bugs in SDK message handling must be fixed in **both** places.

## Verify which source is imported during tests

When running `uv run pytest` from the main workspace, Python imports from the
main `.venv` — NOT from worktree source files. Always `cd` into the worktree
and run from there to test worktree changes.

[channel-dispatch.md]: channel-dispatch.md
[result-message-fallback.md]: result-message-fallback.md
