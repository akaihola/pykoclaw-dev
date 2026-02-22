# WhatsApp Outbound Image Support

## Status: In Progress

## Completed: 2026-02-22

## Priority: 1

## TL;DR

> **Quick Summary**: Enable pykoclaw-whatsapp to send image attachments to users, following the exact same pattern as pykoclaw-matrix. Agents can reference image file paths in their replies, and the bot will upload and send them via WhatsApp.
>
> **Deliverables**:
>
> - `pykoclaw_whatsapp/images.py` - Image path detection (copy from matrix, works for WhatsApp)
> - `pykoclaw_whatsapp/segments.py` - Text/image segment splitting (copy from matrix)
> - Updated connection.py to handle image sending using Neonize's `build_image_message()`
>
> **Estimated Effort**: Low
> **Depends On**: —

---

## Context

### Current State

pykoclaw-whatsapp only sends text messages. When agents output file paths to images, they are sent as literal text strings instead of being uploaded and sent as image attachments.

### Why This Matters

- Agents can generate charts, diagrams, screenshots, or process images and send them to users
- Follows the same pattern already working in pykoclaw-matrix
- Enables rich agent output (graphs, generated images, etc.)

### Technical Path

Neonize (WhatsApp library) supports sending images via `client.build_image_message()` and `client.send_message(jid, message=image_msg)`. This mirrors how Matrix uploads to homeserver - same abstraction, different transport.

The implementation follows pykoclaw-matrix exactly:

1. Detect image file paths in agent's `<reply>` text using regex
2. Split text into TextSegment and ImageSegment objects
3. For each segment: send text normally OR read image file + send as image

---

## Work Objectives

### Core Objective

When an agent outputs an absolute path to an image file within `<reply>` tags, the bot reads the file and sends it as a WhatsApp image message.

### Must Have

#### 1. Create pykoclaw_whatsapp/images.py

- Copy from pykoclaw-matrix/src/pykoclaw_matrix/images.py
- No changes needed - file path detection is platform-agnostic
- Exports: `IMAGE_EXTENSIONS`, `IMAGE_PATH_RE`, `detect_image_paths()`, `mime_for_path()`

#### 2. Create pykoclaw_whatsapp/segments.py

- Copy from pykoclaw-matrix/src/pykoclaw_matrix/segments.py
- Imports from images.py
- Exports: `ImageRef`, `TextSegment`, `ImageSegment`, `Segment`, `split_segments()`

#### 3. Update pykoclaw_whatsapp/connection.py

**Add imports:**

```python
from .images import mime_for_path
from .segments import split_segments, TextSegment, ImageSegment
```

**Add `_send_image()` method:**

```python
def _send_image(self, jid, image_path: Path, caption: str | None = None) -> None:
    """Send an image file via WhatsApp."""
    data = image_path.read_bytes()
    mime = mime_for_path(image_path)
    image_msg = self._client.build_image_message(
        data,
        caption=caption,
        mime_type=mime
    )
    self._client.send_message(jid, message=image_msg)
```

**Modify `_dispatch_for_agent()`** to call a new method instead of directly sending text:

- Extract reply text (existing)
- Call `split_segments(text)` to get ordered segments
- For TextSegment: send as text (existing behavior)
- For ImageSegment: read file, call `_send_image()`

#### 4. Update OutgoingQueue (optional)

The OutgoingQueue currently only handles text. Consider adding `send_image()` method for disconnection resilience, or handle images in the main flow and let queue handle text only.

### Should Have

- Handle missing image files gracefully (log error, skip)
- Handle image read errors gracefully (log exception, continue with other segments)

### Verification

- [ ] Agent outputs `/path/to/image.png` in reply → image sent to WhatsApp
- [ ] Multiple images in one reply → sent in order
- [ ] Mixed text and images → text first, then images in position
- [ ] Missing file → logged, doesn't crash
- [ ] Reconnection → queue flush still works

---

## Dependencies

None - this is independent work.

---

## Notes

- Neonize API: `client.build_image_message(data, caption, mime_type)` → returns message object
- Send with: `client.send_message(jid, message=image_msg)`
- Works for: PNG, JPEG, GIF, WebP, etc.
- Caption support: WhatsApp supports caption on images
- Consider Mermaid rendering later (low priority - matrix has it but WhatsApp doesn't yet)
