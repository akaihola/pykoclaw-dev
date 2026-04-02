# Telegram Image Support (V2)

## Status: Backlog

## Priority: 5

## TL;DR

> **Quick Summary**: Add inbound and outbound image support to the
> `pykoclaw-telegram` plugin. Inbound: receive photos from Telegram chats,
> download via Bot API, and pass to the agent as vision content blocks.
> Outbound: extract image file paths from agent `<reply>` tags and send via
> `sendPhoto` API, interleaved with text segments.
>
> **Deliverables**:
>
> - Inbound photo handler: `PhotoSize`/`Document` updates → download → base64
>   vision content block → dispatch
> - Outbound image pipeline: `<reply>` tag splitting → `sendPhoto` calls with
>   HTML-formatted captions (≤1024 chars)
> - Extended `telegram_messages` table to track attachments
> - Tests for inbound parsing, download mocking, outbound interleaving
>
> **Estimated Effort**: Medium
> **Depends On**: telegram-gateway-plugin

---

## Context

### Current State

The V1 Telegram gateway plugin (see `telegram-gateway-plugin.md`) handles
text-only messaging. Image support is explicitly deferred to V2 to keep the
initial plugin scope manageable — matching the pattern used for WhatsApp
(text gateway first, then `whatsapp-inbound-images` and
`whatsapp-outbound-images` as follow-up plans).

### Why This Matters

Image understanding is the highest-ROI media capability for chat agents:

- "What is this?" / "Translate this sign" / "Debug this screenshot"
- Photo → OCR → structured data (receipts, whiteboards, documents)
- Telegram is often used for quick photo sharing — users expect the bot to
  see what they send

### Technical Path

#### Inbound

Telegram sends photo messages as `Message` objects with a `photo` field
containing an array of `PhotoSize` objects (different resolutions). The bot
downloads the highest-resolution version via `getFile` + HTTPS fetch.

Pipeline: `photo update` → select largest `PhotoSize` → `getFile` API call
→ download bytes → base64-encode → content block in dispatch prompt.

Also handle `document` updates where `mime_type` starts with `image/` (users
sometimes send images as documents to preserve quality).

#### Outbound

Follow the WhatsApp outbound image pattern:

1. Agent includes file paths in `<reply>` tags
2. Gateway splits response into text and image segments
3. Text segments → `sendMessage` with `parse_mode=HTML`
4. Image segments → `sendPhoto` with optional caption (HTML, ≤1024 chars)
5. Preserve interleaving order

#### Formatting interaction

V1 uses HTML for text formatting. Image captions also use `parse_mode=HTML`.
This means the same escaping and tag-stripping logic applies to captions,
keeping the formatting pipeline unified. No special-casing needed.

### Key Decisions

- **Resolution selection**: download the largest `PhotoSize` by default;
  add size limit (e.g. 20 MB) with fallback to a smaller variant
- **Storage**: save downloaded images to disk (like WhatsApp) or keep
  in-memory only for the dispatch? Disk allows re-retrieval for visual
  memory features later
- **Caption splitting**: if agent text before/after an image exceeds 1024
  chars, send as separate `sendMessage` + captionless `sendPhoto`
- **Document images**: handle `document` with image MIME type, or defer?

---

## Work Objectives

### Core Objective

When a user sends a photo to a Telegram chat the bot is in, the agent sees
it as a vision content block and can reason about it. When the agent wants
to share an image, it appears as a native Telegram photo.

### Must Have

- Inbound `photo` update handling with resolution selection
- Download via `getFile` API → base64 content block
- Forwarded to agent through `dispatch_to_agent()` prompt
- Agent can respond to "what's in this photo?" questions
- Outbound image sending via `sendPhoto` API
- `<reply>` tag parsing for file paths (same pattern as WhatsApp)
- Text/image interleaving preserved in outbound
- HTML captions on outbound photos (≤1024 chars)
- Graceful handling of download failures (log warning, text-only fallback)

### Nice to Have

- `document` (image MIME) handling for full-resolution photos
- Image storage on disk for later retrieval / visual memory
- Thumbnail generation for large images
- Grouped media (`MediaGroup`) support for multi-image sends

### Must NOT Have

- No video/audio handling (separate future feature)
- No image generation or editing
- No changes to `pykoclaw-messaging` dispatch interface beyond what V1
  already establishes

---

## Verification Strategy

- Unit test: mock photo update → verify `getFile` called, base64 block built
- Unit test: outbound splitting — text/image/text interleaving
- Unit test: caption truncation at 1024 chars with HTML escaping
- Unit test: download failure → graceful fallback
- Integration: send photo to test chat → verify agent describes it
- Integration: agent response with file path → verify `sendPhoto` delivered
