# Slack Plugin Gotchas

**Tags:** slack, socket-mode, ack, bot-token, threading, slackify-markdown, thread-scoped-sessions
**Related:** [plugin-config-env-file.md], [session-resume-system-prompt.md], [session-resume-retry.md]

## Token types

- `PYKOCLAW_SLACK_BOT_TOKEN` — `xoxb-...` Bot Token. Used for API calls
  (`chat_postMessage`, `reactions_add`, `auth_test`). Standard OAuth bot token.
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
`_bot_user_id` is populated at startup via `auth.test()`. Messages from our
own user ID are always dropped. Other bots are filtered by `allow_bots` config
(default `False`). Both `bot_id` and `subtype == "bot_message"` checks are
kept for edge-case coverage.

## Thread-scoped sessions (effective_channel_id)

Thread replies use `C12345:t:<thread_ts>` as the dispatch key (effective
channel ID). This isolates Claude sessions per thread — two concurrent threads
in the same channel don't share conversation history.

- `make_effective_channel_id(channel_id, thread_ts)` → effective key
- `split_effective_channel_id(effective)` → `(channel_id, thread_ts)`
- DB stores messages with the real `channel_id` + `thread_ts` columns
- `get_new_messages_for_channel(db, effective_id)` filters by thread_ts
  when thread-scoped; returns all channel messages for plain IDs
- Agent cursor (`last_agent_timestamp`) is tracked per effective ID
- `_thread_ts_map` and `_ack_ts_map` are keyed by effective ID

## replyToMode

Configured via `PYKOCLAW_SLACK_REPLY_TO_MODE` (default `all`):
- `'all'` — always reply in thread
- `'first'` — only first reply per effective-channel-id goes in thread
- `'off'` — never thread replies

`_reply_count` dict tracks sent replies per effective channel for `'first'` mode.
Reset on process restart (same trade-off as `_thread_ts_map`).

## ACK reaction (add + remove)

`reactions_add(name=ack_emoji)` is called when a hard mention arrives.
`reactions_remove` is called at the **very start** of `_handle_agent_trigger`
(before the early-return-on-no-messages guard) so it always fires even if
no agent dispatch occurs. Configured via `PYKOCLAW_SLACK_ACK_EMOJI` (default
`eyes`); set to empty string to disable. All reaction API errors are silently
swallowed (best-effort, debug-logged only).

## Channel type inference from ID prefix

Slack channel IDs encode their type:
- `D…` → `im` (DM)
- `C…` → `channel` (public channel)
- `G…` → `group` (private channel / group DM)

`infer_channel_type(channel_id)` in `handler.py` handles this. Used when
`channel_type` is absent from the event — avoids an extra API call. Falls
back to `'channel'` for unknown prefixes.

## slackify-markdown library

`formatting.py` uses `slackify_markdown` (markdown-it-based) instead of
regexes. Key points:
- Library deliberately **disables table support** — pre-process tables first
- Table pre-pass in `_convert_table` converts `| H | H |` to `• **H**: val`
  using Markdown `**bold**` (not `*bold*`) so slackify renders as Slack bold
  (using `*bold*` directly would be re-processed as italic by the library)
- Library adds trailing `\n` — always `.strip()` the result

## app_mention vs message events

Slack fires BOTH `message` and `app_mention` when someone @-mentions the bot
in a channel. Handle `app_mention` with `force_hard_mention=True` to avoid
duplicates while ensuring @-mentions always trigger immediate flush.

## AsyncSocketModeHandler requires aiohttp

`slack_bolt.adapter.socket_mode.aiohttp.AsyncSocketModeHandler` depends on
`aiohttp` internally. This is pulled in by `slack-bolt>=1.20.0` as a default dep.

## uv worktree sync requires --all-packages

Running `uv sync` in a worktree only installs workspace-root deps. To install
all workspace members (including `pykoclaw-slack`), use `uv sync --all-packages`.
Tests must run with `uv run --all-packages pytest` for the same reason.

[plugin-config-env-file.md]: plugin-config-env-file.md
[session-resume-system-prompt.md]: session-resume-system-prompt.md
[session-resume-retry.md]: session-resume-retry.md
