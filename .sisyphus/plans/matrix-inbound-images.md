# Matrix Inbound Image Support (Vision)

## Status: Backlog

## Priority: 1

## TL;DR

> **Quick Summary**: Enable pykoclaw-matrix to receive images from Matrix rooms
> and pass them to Claude's vision API. Users send photos and the agent can
> describe, OCR, debug screenshots, translate signs, etc. This is the
> highest-value media addition — Claude has native vision and the upload/download
> infrastructure already exists in matrix-nio.
>
> **Deliverables**:
>
> - `RoomMessageImage` event callback in `connection.py`
> - Image download via `client.download()` → base64 content block
> - Extended message storage to track image attachments
> - Image content blocks forwarded to `dispatch_to_agent()` prompt
>
> **Estimated Effort**: Medium
> **Depends On**: —

---

## Context

### Current State

`connection.py` only registers a callback for `RoomMessageText`. Images sent to
rooms the bot is in are silently ignored. The agent never knows a photo was
shared.

### Why This Matters

Image understanding is the single highest-ROI media capability:

- "What is this?" / "Translate this sign" / "Debug this screenshot"
- Photo → OCR → structured data extraction (receipts, whiteboards, documents)
- Visual memory: users send photos, agent describes and stores them for later
  retrieval ("what was on Monday's whiteboard?")

### Technical Path

matrix-nio provides `RoomMessageImage` events with `url` (mxc:// URI) and
`body` (filename). The client's `download()` method fetches the actual bytes.
Claude accepts base64-encoded images as content blocks in the prompt. The
existing `_send_image` method shows the upload side already works — this is the
symmetric download path.

### Key Decisions Needed

- **Message storage**: the `matrix_messages` table stores `text`. Need to decide
  whether to add an `attachments` column (JSON blob with base64 or file paths)
  or store images as files on disk and reference them.
- **Prompt construction**: `format_xml_messages()` currently emits text-only XML.
  Need to extend it (or the dispatch call) to include image content blocks
  alongside text in the agent prompt.
- **Size limits**: Large images should be resized or rejected. Matrix thumbnails
  could be used as a fallback for huge originals.

### Supported Formats

JPEG, PNG, GIF (including animated — first frame for vision), WebP, SVG.
Claude's vision API supports JPEG, PNG, GIF, and WebP natively.

---

## Work Objectives

### Core Objective

When a user sends an image to a Matrix room the bot is in, the agent sees it
as a vision content block and can reason about it.

### Must Have

- `RoomMessageImage` callback registered in `_register_callbacks()`
- Image bytes downloaded via `client.download()` from mxc:// URI
- Image forwarded to agent as base64 content block (Anthropic vision format)
- Agent can respond to "what's in this image?" type questions
- Images in DMs and hard-mention contexts trigger the agent
- Graceful handling of download failures (log warning, skip image)

### Nice to Have

- Thumbnail fallback for images > 5 MB
- Image stored on disk for later retrieval / visual memory
- Support for `RoomEncryptedImage` (E2EE rooms)

### Must NOT Have

- No image generation (that's outbound, separate feature)
- No video frame extraction (separate feature)
- No modification of `pykoclaw-messaging` dispatch signature (pass images
  through the existing prompt string + content blocks mechanism)

---

## Verification Strategy

- Unit test: mock `RoomMessageImage` event → verify download called, base64
  block constructed
- Unit test: `format_xml_messages` with image attachment → verify content block
  structure
- Integration: send an image to a test room → verify agent responds with
  description
