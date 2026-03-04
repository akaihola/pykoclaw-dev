# Slack Plugin Gotchas

**Tags:** slack, socket-mode, ack, bot-token, threading, slackify-markdown, thread-scoped-sessions, inbound-images, vision
**Related:** [plugin-config-env-file.md], [session-resume-system-prompt.md], [session-resume-retry.md], [slack-reply-extraction.md]

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

## Inbound image support (attachments.py)

When a user uploads an image to Slack, the `message` event carries a `files`
array with `url_private_download`, `mimetype`, and `id`. Key points:

- `attachments.py` handles download: `extract_image_files()` filters to
  `VISION_MIMETYPES`; `download_slack_image()` fetches with
  `Authorization: Bearer <bot_token>`; `download_event_images()` orchestrates.
- Files stored at `{data_dir}/slack_attachments/{channel_id}/{file_id}.{ext}`.
- `handler.py` returns 4-tuples: `(sender, timestamp, text, attachment_paths)`.
  `get_new_messages_for_channel` returns `list[str] | None` for attachment paths.
- `format_xml_message` emits `<attachment type="image" path="..."/>` inside
  `<message>` when paths are present — the agent calls `analyze_image` with
  the path.
- `slack_messages` table has `attachment_path TEXT` column (added via
  `ALTER TABLE` migration — run_db_migrations catches the OperationalError if
  column already exists).
- Image-only messages (text="" but files present) are now accepted — the
  previous `if not text: return` guard became `if not text and not has_files`.
- `pykoclaw-vision` added to `pyproject.toml` deps; `make_analyze_image_tool()`
  registered in `get_mcp_servers()`.
- Requires `files:read` OAuth scope on the Slack app.

## Cross-domain redirect drops auth header (image download gotcha)

`url_private_download` redirects from `files.slack.com` to
`workspace.slack.com`. **httpx silently strips the `Authorization` header on
cross-domain redirects** (security feature). Slack sees the unauthenticated
request and returns `200 OK` with an HTML login page — `raise_for_status()`
doesn't catch it, so the HTML gets written as a `.png` and Gemini rejects it
with 400 Bad Request.

Three-layer defence in `download_slack_image()`:

1. **Re-inject auth on every leg** — `event_hooks={"request": [_inject_auth]}`
   re-adds `Authorization: Bearer <token>` for each request including redirects.
2. **Validate Content-Type** — response must be an image MIME (`VISION_MIMETYPES`);
   `text/html` or anything unexpected → log warning, return `None`.
3. **Evict stale HTML cache** — `_looks_like_html(path)` checks the first 16 bytes
   for `<!doctype` / `<html`. If a cached file is HTML, it's deleted and
   re-downloaded rather than returned as-is.

Committed in pykoclaw-slack `2b74d23`.

[plugin-config-env-file.md]: plugin-config-env-file.md
[session-resume-system-prompt.md]: session-resume-system-prompt.md
[session-resume-retry.md]: session-resume-retry.md
[slack-reply-extraction.md]: slack-reply-extraction.md
