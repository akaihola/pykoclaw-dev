# Slack Inbound Image Support (Vision)

## Status: Done

## Completed: 2026-03-04

## Priority: 2

## TL;DR

> **Quick Summary**: Enable pykoclaw-slack to receive images shared in Slack
> channels and pass them to Claude via the `analyze_image` MCP tool. Users share
> screenshots, photos, or diagrams and the agent can describe, OCR, or reason
> about them. Follows the same pattern as WhatsApp and Matrix inbound images.
>
> **Deliverables**:
>
> - Image file detection in `handler.py` (parse `files` array on message events)
> - Image download via `httpx` using the Slack Bot Token (`url_private_download`)
> - Storage on disk in a per-channel attachments directory
> - `make_analyze_image_tool()` from `pykoclaw-vision` wired into `get_mcp_servers()`
> - Agent can respond to "what's in this image?" type questions
>
> **Estimated Effort**: Small–Medium
> **Depends On**: pykoclaw-vision (already extracted and available)

---

## Context

### Current State

`handler.py` extracts only the `text` field from Slack message events. The
`files` array that Slack attaches when a user uploads an image is silently
ignored. `get_mcp_servers()` in `__init__.py` only registers `send_slack_message`
and `get_slack_history` — `analyze_image` is not available to the agent.

### Why This Matters

Image sharing is extremely common in team Slack workspaces:

- "Here's the error screenshot — what's wrong?" / "What does this diagram say?"
- Photo → OCR → structured data extraction (receipts, whiteboards, documents)
- Design review: share a mockup, ask for feedback
- Quick knowledge capture: photo of a whiteboard

### Technical Path

Slack attaches a `files` array to `message` events when the user uploads files.
Each file entry has:

- `url_private_download` — authenticated download URL
- `mimetype` — e.g. `image/jpeg`, `image/png`
- `id` — unique file ID
- `name` — original filename

Downloads require an HTTP `GET` with `Authorization: Bearer <bot_token>`.
`httpx` is already a transitive dependency; `PYKOCLAW_SLACK_BOT_TOKEN` is
already available in `SlackSettings`.

The `pykoclaw-vision` package (`make_analyze_image_tool()`) is already
extracted and used by pykoclaw-whatsapp — this plan just wires it into the
Slack plugin identically.

---

## Work Objectives

### Must Have

- Detect `files` in incoming Slack message events (image types only, Phase 1)
- Download images via `httpx` with bot-token auth; store in
  `{data_dir}/slack_attachments/{channel_id}/{file_id}.{ext}`
- Store attachment path alongside the message in `slack_messages` DB
- Include attachment path in `format_xml_messages()` output
- `make_analyze_image_tool()` registered in `get_mcp_servers()`
- Works in DMs and channels; hard-mention and batch-flush paths both handle attachments
- Graceful failure: download errors → log warning, continue with text only

### Nice to Have

- Thumbnail fallback for images > 5 MB (download thumbnail instead of original)
- `files_share` subtype support (file shared without text — Slack sends a
  separate `message` event with `subtype: files_share`)
- Track file downloads in DB to avoid re-downloading on reconnect

### Must NOT Have

- No image generation (outbound, separate feature)
- No non-image file handling in Phase 1 (PDFs, documents — separate feature)
- No modification of `pykoclaw-messaging` dispatch signature

---

## Implementation Plan

### 1. `attachments.py` (new file)

Add `pykoclaw-slack/src/pykoclaw_slack/attachments.py`:

```python
VISION_MIMETYPES = frozenset({"image/jpeg", "image/png", "image/gif", "image/webp"})

async def download_slack_image(
    url: str, bot_token: str, dest: Path
) -> Path | None:
    """Download *url* with bearer auth and write to *dest*. Returns path or None."""
    ...
```

Uses `httpx.AsyncClient` with `Authorization: Bearer <bot_token>`.

### 2. `handler.py`

- Add `extract_image_files(event_payload) -> list[dict]` — filters `files` list
  to vision-capable mime types.
- Update `store_and_flush()` (or equivalent) to call `download_slack_image()`
  for each image file and record the attachment path.
- Extend `get_new_messages_for_channel()` return type to carry
  `attachment_path: str | None`.
- Update `format_xml_messages()` to emit
  `<attachment type="image" path="..."/>` when present.

### 3. DB migration

Add `attachment_path TEXT` column to `slack_messages` via `ALTER TABLE ADD COLUMN`
in `get_db_migrations()` (with `IF NOT EXISTS` guard or idempotent retry logic).

### 4. `__init__.py` — wire in vision tool

```python
from pykoclaw_vision import make_analyze_image_tool

def get_mcp_servers(self, db, conversation):
    ...
    return {
        "slack": create_sdk_mcp_server(
            name="slack",
            tools=[send_slack_message, get_slack_history, make_analyze_image_tool()],
        )
    }
```

Add `pykoclaw-vision` to `pykoclaw-slack/pyproject.toml` dependencies.

---

## Slack API Requirements

The existing `files:read` OAuth scope must be present on the Slack app. If not
yet granted, the Slack app manifest needs updating. `url_private_download` is
only accessible with a valid bot token — direct HTTP GET without auth returns a
redirect to an HTML login page.

---

## File Changes

```
pykoclaw-slack/
├── src/pykoclaw_slack/
│   ├── attachments.py      # NEW: download + store logic
│   ├── handler.py          # detect files, download, extend XML format
│   └── __init__.py         # add make_analyze_image_tool to MCP server
├── pyproject.toml          # add pykoclaw-vision dependency
└── tests/
    └── test_attachments.py # NEW: mock httpx, verify download + storage
```

---

## Verification Strategy

- Unit test: message event with `files` array → verify `download_slack_image`
  called with correct URL and token
- Unit test: download failure → verify graceful skip, text message still
  dispatched
- Unit test: `format_xml_messages` with attachment path → verify
  `<attachment type="image" .../>` in output
- Integration: upload image to Slack → verify stored on disk, agent describes it

---

## Related Plans

- [whatsapp-inbound-images.md](./whatsapp-inbound-images.md) — reference implementation (Done)
- [matrix-inbound-images.md](./matrix-inbound-images.md) — parallel feature for Matrix
- [slack-gateway-plugin.md](./slack-gateway-plugin.md) — base Slack plugin
- [attachment-support.md](./attachment-support.md) — ACP attachment support (separate)
