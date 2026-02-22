# WhatsApp Inbound Image Support (Vision)

## Status: Backlog

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

- [ ] Image messages detected and trigger agent (like text)
- [ ] Images downloaded via `client.download_any()`
- [ ] Images stored in conversation attachments directory
- [ ] `analyze_image` MCP tool available to agent
- [ ] Agent can describe images when asked
- [ ] Works in DMs and group chats
- [ ] Graceful handling of download failures

## Nice to Have

- [ ] Thumbnail generation for large images (>5MB)
- [ ] Automatic OCR with text extraction
- [ ] Image stored for visual memory / retrieval
- [ ] Video key frame extraction
- [ ] Document text extraction (OCR)

## Must NOT Have

- [ ] No image generation (outbound, separate feature)
- [ ] No modification to core dispatch signature
- [ ] No video frame analysis in Phase 1

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

- **Anthropic API key**: For vision capability (ANTHROPIC_API_KEY or configured)
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
