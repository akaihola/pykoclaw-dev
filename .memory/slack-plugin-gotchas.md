# Slack Plugin Gotchas

**Tags:** slack, socket-mode, ack, bot-token, threading
**Related:** [plugin-config-env-file.md], [session-resume-system-prompt.md], [session-resume-retry.md]

## Token types

- `PYKOCLAW_SLACK_BOT_TOKEN` — `xoxb-...` Bot Token. Used for API calls
  (`chat_postMessage`, `auth_test`). Standard OAuth bot token.
- `PYKOCLAW_SLACK_APP_TOKEN` — `xapp-...` App-Level Token. Required for
  Socket Mode. Create in Slack app settings under "App-Level Tokens" with
  `connections:write` scope.

Both must be set; `slack run` exits with error if either is missing.

## Slack requires ack() within 3 seconds

`@app.event(...)` handlers MUST call `await ack()` as the FIRST thing,
before any I/O. If ack isn't sent within 3 seconds, Slack retries the
event — causing double processing. The BatchAccumulator's `add()`/`flush_now()`
are fast; slow agent dispatch happens asynchronously after ack.

## Bot self-message loop

Slack delivers the bot's own `chat_postMessage` output as a `message` event.
Filter `event.get("bot_id")` or `event.get("subtype") == "bot_message"` at
the top of `_handle_message`. Both checks are needed — `bot_id` is set on
messages from bots, `subtype` covers some edge cases.

## Thread-aware replies

`_thread_ts_map[channel_id]` records the `thread_ts` (or `ts`) of the
triggering message. Replies use this to stay in-thread. This is in-memory only
(not persisted); process restart loses the thread context for the next reply.

## app_mention vs message events

Slack fires BOTH `message` and `app_mention` when someone @-mentions the bot
in a channel. Handle `app_mention` with `force_hard_mention=True` to avoid
duplicates while ensuring @-mentions always trigger immediate flush.

## AsyncSocketModeHandler requires aiohttp

`slack_bolt.adapter.socket_mode.aiohttp.AsyncSocketModeHandler` depends on
`aiohttp` internally. This is pulled in by `slack-bolt[async]` or modern
`slack-bolt>=1.20.0` as a default dep.

[plugin-config-env-file.md]: plugin-config-env-file.md
[session-resume-system-prompt.md]: session-resume-system-prompt.md
[session-resume-retry.md]: session-resume-retry.md
