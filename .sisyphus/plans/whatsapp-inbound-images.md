# WhatsApp Inbound Image Support (Vision)

## Status: In Progress

## Priority: 1

## TL;DR

> **Quick Summary**: Enable pykoclaw-whatsapp to receive images from WhatsApp
> chats and allow Claude to analyze them. Users send photos and the agent can
> describe, OCR, debug screenshots, translate signs, etc.
>
> **Deliverables**:
>
> - Image message detection in `handler.py`
> - Image download via Neonize's `client.download_any()`
> - Storage on disk in conversation attachments directory
> - MCP tool `analyze_image` to pass images to Anthropic vision API
> - Agent can respond to "what's in this image?" type questions
>
> **Estimated Effort**: Medium
> **Depends On**: —

---

## Context

### Current State

The WhatsApp plugin in `handler.py` only extracts text from messages via
`extract_text()`. Images, videos, documents, and stickers are silently ignored.
Non-text messages simply don't trigger the agent at all.

### Why This Matters

Image understanding is high-value:

- "What is this?" / "Translate this sign" / "Debug this screenshot"
- Photo → OCR → structured data extraction (receipts, whiteboards, documents)
- Visual memory: users send photos, agent describes and stores them
- Agent can see screenshots of errors, diagrams, documents

### Technical Path

Neonize provides `client.download_any(message)` to download any media from a
WhatsApp message. The `ImageMessage` protobuf contains:

- `URL` / `directPath` - the download location
- `mediaKey` - decryption key
- `mimetype` - media type
- `fileLength` - size

The Claude Agent SDK doesn't natively support vision content blocks, so we'll
use an MCP tool approach: download images to disk, provide an `analyze_image`
tool that calls the Anthropic API directly with vision capabilities.

---

## Research Summary

### Reference: whatsapp-chatgpt-python

The [green-api/whatsapp-chatgpt-python](https://github.com/green-api/whatsapp-chatgpt-python)
project demonstrates a clean handler pattern:

```
handlers/
├── image.py      # Returns content blocks for vision models
├── video.py      # Similar pattern
├── audio.py      # Transcription with Whisper
├── document.py   # File handling
└── registry.py   # Routes messages to handlers
```

Their image handler:

1. Checks if model supports images (`is_image_capable_model`)
2. Validates format (png, jpg, jpeg, gif, webp)
3. Returns content blocks or fallback text

### Claude Vision API Format

```python
{
    "type": "image",
    "source": {
        "type": "base64",
        "media_type": "image/jpeg",
        "data": "<base64-data>"
    }
}
```

### Size Limits

- Max request size: 32MB
- Max images per request: 100 (API), 20 (claude.ai)
- Recommended: ≤1 megapixel, ≤1568px on longest edge
- Supported formats: JPEG, PNG, GIF, WebP

---

## Implementation Plan

### Phase 1: Image Download & Storage

1. **Extend `handler.py`**:
   - Add detection for `imageMessage`, `videoMessage`, `documentMessage`,
     `stickerMessage`, `audioMessage` in message types
   - Add `download_attachment()` function using `client.download_any()`
   - Store in `{data_dir}/conversations/{conversation}/attachments/{msg_id}.{ext}`

2. **Add attachment tracking**:
   - Create `wa_attachments` table or extend existing schema
   - Track: message_id, chat_jid, media_type, file_path, caption, timestamp

### Phase 2: MCP Tool for Vision

3. **Create `analyze_image` MCP tool** in `pykoclaw-messaging` or `pykoclaw-whatsapp`:

   ```python
   @mcp.tool()
   def analyze_image(path: str, question: str = "Describe this image") -> str:
       """Analyze an image using Claude's vision capabilities."""
       # Read image, convert to base64, call Anthropic API
   ```

4. **Add tool to extra_mcp_servers** in WhatsApp connection setup

### Phase 3: Agent Integration

5. **Update message format**:
   - When an image is received, include in XML context:
     ```xml
     <message sender="user" time="...">
       <text>Check out this</text>
       <attachment type="image" path="/path/to/image.jpg" />
     </message>
     ```

6. **System prompt update**:
   - Inform agent about the `analyze_image` tool
   - Tell agent to use it when users send images

### Phase 4: Error Handling

7. **Graceful degradation**:
   - Download failures: log warning, skip image, continue with text
   - Unsupported format: notify user or skip silently
   - Large files: resize before analysis or use thumbnail
   - API failures: retry with backoff

---

## Technical Decisions Needed

### 1. Message Storage Strategy

Options:

- **A**: Store attachments on disk, reference paths in DB (recommended)
- **B**: Store base64 directly in DB (not recommended - large)
- **C**: Store in memory only, lose on restart (simplest but fragile)

Decision: A - files on disk with DB reference

### 2. Image Format for Agent Context

Options:

- **A**: Always download and include base64 in prompt (most capable)
- **B**: Only include file path, agent uses analyze_image tool (simpler, on-demand)
- **C**: Hybrid - small images inline, large via tool

Decision: B - agent uses tool for analysis, keeps core interface clean

### 3. Handling Multiple Images

- Batch messages may contain multiple images
- Include all in attachment list, agent can analyze each

### 4. Video Handling

- Videos are complex (large files, frames)
- Start with images only, defer video to Phase 2

### 5. Claude SDK vs Raw API

The Claude Agent SDK doesn't support vision content blocks natively.
We have two options:

- **Option A**: MCP tool approach (current recommendation)
- **Option B**: Modify dispatch signature to accept content blocks

Decision: Option A - MCP tool keeps changes localized

### 6. Vision API client (codebase investigation finding)

The `anthropic` Python package is **not installed** in the workspace. Use `httpx`
(already a transitive dependency) to call the Anthropic API directly. The
system-wide `ANTHROPIC_API_KEY` and `ANTHROPIC_BASE_URL` env vars are already set.

### 7. DB schema for attachments (codebase investigation finding)

`run_db_migrations()` uses `db.executescript(sql)` wrapped in a single try/except
per migration string. Adding `ALTER TABLE ADD COLUMN` to `wa_messages` would log a
noisy error on every subsequent startup. Use a separate `wa_attachments` table
(`CREATE TABLE IF NOT EXISTS`) instead — it's idempotent.

### 8. `download_any` argument (codebase investigation finding)

`client.download_any()` takes the full `MessageEv` event (=
`neonize.proto.Neonize_pb2.Message`), not the inner `event.Message` field. Message
ID is at `event.Info.ID`.

### 9. Return type of `get_new_messages_for_chat` (codebase investigation finding)

Change from `list[tuple[str, str, str]]` → `list[tuple[str, str, str | None, str | None]]`
(sender, timestamp, text, attachment_path). Update all callers: `format_xml_messages()`,
`_handle_agent_trigger()` in connection.py, and `get_chat_history` MCP tool.

---

## Supported Formats

| Media Type                   | Download | Store | Analyze | Notes         |
| ---------------------------- | -------- | ----- | ------- | ------------- |
| Image (JPEG, PNG, GIF, WebP) | ✅       | ✅    | ✅      | Primary focus |
| Image (other)                | ✅       | ✅    | ❌      | Store only    |
| Video                        | ✅       | ✅    | ❌      | Future work   |
| Document                     | ✅       | ✅    | ❌      | Future work   |
| Audio                        | ✅       | ✅    | ❌      | Future work   |
| Sticker                      | ✅       | ✅    | ❌      | Future work   |

---

## Must Have

- [x] Image messages detected and trigger agent (like text)
- [x] Images downloaded via `client.download_any()`
- [x] Images stored in conversation attachments directory
- [x] `analyze_image` MCP tool available to agent
- [x] Agent can describe images when asked
- [x] Works in DMs and group chats
- [x] Graceful handling of download failures

## Nice to Have

- [ ] Thumbnail generation for large images (>5MB)
- [ ] Automatic OCR with text extraction
- [ ] Image stored for visual memory / retrieval
- [ ] Video key frame extraction
- [ ] Document text extraction (OCR)

## Must NOT Have

- [x] No image generation (outbound, separate feature)
- [x] No modification to core dispatch signature
- [x] No video frame analysis in Phase 1

---

## File Changes

### pykoclaw-whatsapp/

```
src/pykoclaw_whatsapp/
├── handler.py          # Add attachment extraction
├── attachments.py      # NEW: Download & storage logic
├── mcp_tools.py       # NEW: analyze_image tool
└── connection.py      # Register handlers, add tool to extra_mcp_servers
```

### pykoclaw-messaging/

```
src/pykoclaw_messaging/
├── dispatch.py         # May need extension for content blocks
└── tools.py           # Add analyze_image here? Or in whatsapp?
```

---

## Verification Strategy

### Unit Tests

- [ ] `test_extract_attachments` - verify image/video detection
- [ ] `test_download_and_store` - mock Neonize client, verify storage
- [ ] `test_analyze_image_tool` - mock Anthropic API, verify response parsing

### Integration Tests

- [ ] Send image to WhatsApp → verify download to disk
- [ ] Ask agent about image → verify vision analysis in response
- [ ] Multiple images in batch → verify all processed

### Manual Testing

1. Send photo via WhatsApp
2. Ask "what's in this image?"
3. Verify agent provides description

---

## Dependencies

- **Gemini API key**: For vision capability (`GEMINI_API_KEY`, defaults to
  `gemini-3.1-flash-lite-preview`, override via `PYKOCLAW_WA_VISION_MODEL`)
- **Disk space**: For attachment storage
- **Network**: For downloading from WhatsApp CDN

---

## Related Plans

- [matrix-inbound-images.md](./matrix-inbound-images.md) - Similar feature for Matrix
- [wa-ambient-participation.md](./wa-ambient-participation.md) - Already implemented

---

## Notes

- Neonize's `download_any()` works with the full `Message` object from `MessageEv`
- WhatsApp media URLs expire, so we must download immediately
- The handler pattern from whatsapp-chatgpt-python could be adopted for cleaner
  separation, but incremental change to existing handler.py is simpler
- Vision is handled via the Gemini API (not Anthropic): model defaults to
  `gemini-3.1-flash-lite-preview`, set `GEMINI_API_KEY` in the environment

---

## Phase 2 (Future): Extract vision plugin

**Status:** Done (extracted in this worktree before merge)  
**Depends on:** Phase 1 (complete)

### Rationale

Image vision (`analyze_image`) and generation (`generate_image`, `edit_image`)
will be needed by all channel plugins (WhatsApp, Matrix, Slack). Duplicating
the Gemini client, model selection, and tool definitions in every plugin is
wasteful. Extract to a shared `pykoclaw-vision` package.

### New package: pykoclaw-vision

A new workspace member with **no CLI, no entry points, no DB migrations** —
pure Python library exporting MCP tool factories.

```
pykoclaw-vision/
├── src/pykoclaw_vision/
│   ├── __init__.py      # exports: make_analyze_image_tool,
│   │                    #         make_generate_image_tool,
│   │                    #         make_edit_image_tool
│   └── vision.py        # shared Gemini client, model config
├── pyproject.toml
└── tests/
```

### Exports

The vision plugin exports factory functions that channel plugins call:

```python
# In each channel plugin's get_mcp_servers()
from pykoclaw_vision import (
    make_analyze_image_tool,
    make_generate_image_tool,
    make_edit_image_tool,
)

def get_mcp_servers(...):
    return {
        "whatsapp": create_sdk_mcp_server(
            name="whatsapp",
            tools=[send_message, get_chat_history,
                   make_analyze_image_tool(),
                   make_generate_image_tool(),
                   make_edit_image_tool()],
        )
    }
```

### Configuration

Shared between all plugins via environment:

- `GEMINI_API_KEY` — required, read by the vision plugin
- `PYKOCLAW_VISION_MODEL` — override for image analysis, default: `gemini-3.1-flash-lite-preview`
- `PYKOCLAW_IMAGE_MODEL` — override for image generation/editing, default: `gemini-3.1-flash-image-preview`

### Migration steps

1. Create `pykoclaw-vision/` repo with workspace member and stub package
2. Move `attachments.py:make_analyze_image_tool()` → `pykoclaw-vision/vision.py`
3. Add `make_generate_image_tool()` and `make_edit_image_tool()` factories
4. In `pykoclaw-whatsapp`, `import from pykoclaw_vision` instead of local
5. Update plan `wa-outbound-images.md` when it resumes to use the extracted
   tools instead of duplicating
6. Update `matrix-inbound-images.md`, `slack-gateway` plans to import from
   pykoclaw-vision

### Why not pykoclaw-messaging?

`pykoclaw-messaging` is the routing/dispatch layer — it knows about conversation
lookup, agent dispatch, session management. Mixing vision API helpers in there
adds an unrelated dependency. A vision plugin has a clear single responsibility.

### Why a proper package and not a module in pykoclaw-core?

Vision capabilities may have large dependencies (Pillow, possibly video
processing libraries). Keeping them isolated in their own dependency group
means users who don't need vision don't pull them in.
