# Slack Plugin Gotchas

**Tags:** slack, socket-mode, ack, bot-token, threading, slackify-markdown, thread-scoped-sessions, inbound-images, vision, response-transformer, pykofinder
**Related:** [plugin-config-env-file.md], [session-resume-system-prompt.md], [session-resume-retry.md], [slack-reply-extraction.md], [agent-output-pipeline.md]

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

`reactions_add(name=ack_emoji)` is called when a hard mention arrives,
immediately and before `flush_now`.

`reactions_remove` is called **after `dispatch_to_agent` completes** so
`:eyes:` (or whatever emoji) stays visible the entire time the agent is
thinking. The `ack_ts` is popped from `_ack_ts_map` eagerly to claim
ownership, but the API call is deferred. One exception: when
`get_new_messages_for_channel` returns an empty list (race / cursor already
advanced), there is no agent call and the reaction is removed in the early-
exit branch so it doesn't linger.

Configured via `PYKOCLAW_SLACK_ACK_EMOJI` (default `eyes`); set to empty
string to disable. All reaction API errors are silently swallowed
(best-effort, debug-logged only).

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

## Required Slack OAuth bot token scopes

Current scopes needed for full functionality:

| Scope                                                                 | Used for                                          |
| --------------------------------------------------------------------- | ------------------------------------------------- |
| `chat:write`                                                          | `chat_postMessage`                                |
| `reactions:write`                                                     | ACK emoji reactions                               |
| `channels:history` / `groups:history` / `im:history` / `mpim:history` | reading message history                           |
| `channels:read`                                                       | channel info                                      |
| `app_mentions:read`                                                   | `app_mention` events                              |
| `files:write`                                                         | **`files_upload_v2` — image uploads**             |
| `files:read`                                                          | downloading Slack-uploaded files (inbound images) |

**`files:write` is required for outbound image upload.** Without it,
`files.getUploadURLExternal` returns `missing_scope` and the upload silently
fails (exception is caught and logged). The prose text still posts; only the
image is missing. Add scopes at api.slack.com/apps → OAuth & Permissions →
Bot Token Scopes, then reinstall to workspace to get a new `xoxb-` token.

## Outbound image embeds: download + upload via files_upload_v2

When the agent produces `![alt](https://gogo.crane-boa.ts.net:8445/w/...)`,
`slackify_markdown` converts it to a plain `<url|alt>` hyperlink — not a
visible image. `outbound_images.py` intercepts these **before** mrkdwn
conversion in `_send_message`:

1. `extract_image_embeds(text)` — strips all `![alt](https://...)` tokens,
   returns `ExtractResult(cleaned_text, images)`.
2. Prose (if any) posted first via `chat_postMessage` so context appears above images.
3. Each image downloaded with `httpx` (no auth, Tailscale-internal) and
   uploaded via `files_upload_v2` (3-step getUploadURL → PUT → complete).
4. Image-only reply: alt used as `initial_comment`. Reply with prose: comment
   omitted to avoid repeating text already posted.
5. HTML content-type response → skip + warning. Any error → log + swallow.

Plain `[label](url)` links are NOT extracted — `slackify_markdown` already
handles them as `<url|label>` Slack hyperlinks. Committed `38af722`.

## response_transformer must be wired through SlackConnection

Like Matrix and WhatsApp, the Slack `run` command must:

1. Call `load_plugins()` to get all plugins (not just `[SlackPlugin()]`).
2. Build a `compose_transformers(all_plugins, TransformContext(...))` with
   `channel_prefix="slack"` and `native_file_extensions=frozenset()` (Slack
   cannot serve local file bytes — it needs HTTP URLs).
3. Pass `response_transformer=` to `SlackConnection.__init__`.
4. `SlackConnection` stores it as `self._response_transformer` and passes it
   to all three `dispatch_to_agent()` call sites.

Without this, pykofinder (and any other plugin transformers) never run on
Slack responses. Image paths like `![alt](~/coleaders/docs/.../kuva.png)`
appear as raw Markdown text in Slack instead of being converted to pykofinder
HTTP URLs. Fixed in pykoclaw-slack commit `b371281` (Pi-Session d0a4058c).

## pykofinder does not expand ~/... paths (fixed)

`transform.py` previously treated `~/path` as a relative path joined onto
`workspace_root`, producing `/w/pykoclaw/~/...` in the URL instead of
expanding the home directory. Fixed by checking `target.startswith("~")` and
calling `Path(target).expanduser()` in both `_replace_markdown_link` and
`_replace_html_img`. Fixed in pykoclaw-pykofinder commit `6ea4cef`
(Pi-Session d0a4058c).

[plugin-config-env-file.md]: plugin-config-env-file.md
[session-resume-system-prompt.md]: session-resume-system-prompt.md
[session-resume-retry.md]: session-resume-retry.md
[slack-reply-extraction.md]: slack-reply-extraction.md
