# New Channel Plugin Checklist

When building a new messaging/channel plugin (Matrix, Telegram, Slack, etc.):

1. **Verify third-party API semantics** — never trust property names; confirm with
   source reading or a quick REPL test.
2. **Configure logging** — long-running `run` commands must call
   `logging.basicConfig()` or all log output is silently lost.
3. **Validate required config upfront** — check credentials/URLs before
   starting the event loop. Show a friendly `click.echo` error with remediation
   steps, not a traceback.
4. **Respect `*_DATA` env vars for `.env` resolution** — resolve paths from
   the environment variable so custom data directories work.
5. **Add log lines for message receipt + trigger decisions** — without these,
   debugging "bot doesn't respond" is blind guesswork.
6. **Send typing/presence indicators** — send platform-specific "typing" signals
   before dispatch and clear them after.
7. **Retry `dispatch_to_agent()` without session resume** — wrap dispatch in
   try/except, clear the session_id via `upsert_conversation`, and retry.
   See [session-resume-retry.md].
8. **Update docs as you add features** — every CLI command, config option,
   and setup step should be in the README before committing.

[session-resume-retry.md]: ../.memory/session-resume-retry.md
