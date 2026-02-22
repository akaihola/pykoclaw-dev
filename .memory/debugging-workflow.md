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

## Check service file for log locations FIRST

Don't start with `journalctl` — it often only shows systemd start/stop
messages. Read the `.service` file first:

```bash
cat ~/.config/systemd/user/pykoclaw-matrix.service
```

Look for `StandardOutput=append:` / `StandardError=append:` — the actual
application logs are there (e.g. `~/.local/state/pykoclaw/matrix.log`).
Only fall back to `journalctl` if logs go to the journal.

## DB schema before queries

Always run `.schema <table>` before writing `SELECT` queries against
unfamiliar tables. Column names are not guessable (e.g. `conversations`
uses `name` as PK, not `id`).

## Dispatch timing as failure signal

When an agent "chose silence", check how long the dispatch took:

| Duration | Meaning                                                                                                     |
| -------- | ----------------------------------------------------------------------------------------------------------- |
| < 2s     | **Subprocess startup failure** — claude exited before processing. Check `~/.claude/debug/<session_id>.txt`. |
| 2–5s     | Possible failure or very short response                                                                     |
| ≥ 5s     | Normal — Claude made an actual API call                                                                     |

A dispatch that returns `full_text=''` in under 2 seconds is almost never
genuine silence — it's a silent subprocess crash.

## Claude CLI debug artifacts

Every claude subprocess invocation writes:

- **`~/.claude/debug/<session_id>.txt`** — full startup/shutdown trace.
  Check line count: < 60 lines = died during init, no API call was made.
- **`~/.claude/projects/<project_hash>/<session_id>.jsonl`** — session
  history file. Missing = subprocess never wrote it = died before doing work.

The `project_hash` is derived from the `cwd` option passed to
`ClaudeAgentOptions`. For WhatsApp: `data_dir/conversations/<conv_name>`.

Find the session ID from `conversations` table, then check both files
immediately — this shortcuts most silent-failure investigations.

[channel-dispatch.md]: channel-dispatch.md
[result-message-fallback.md]: result-message-fallback.md
