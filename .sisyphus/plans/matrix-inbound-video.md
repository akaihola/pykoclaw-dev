# Matrix Inbound Video Understanding

## Status: Backlog

## Priority: 3

## TL;DR

> **Quick Summary**: Enable the agent to understand video files shared in Matrix
> rooms by extracting keyframes and (optionally) transcribing audio. ffmpeg is
> already available on the system. This could be implemented as a skill rather
> than baked into the connection layer — the connection just needs to download
> the video and hand it off.
>
> **Deliverables**:
>
> - `RoomMessageVideo` event callback in `connection.py`
> - Video download via `client.download()` → temp file
> - Keyframe extraction via ffmpeg → images → Claude vision
> - Optional audio track extraction → transcription (reuse inbound audio backend)
> - Agent sees keyframes + transcript in prompt context
>
> **Estimated Effort**: Medium
> **Depends On**: matrix-inbound-images

---

## Context

### Current State

Video files sent to Matrix rooms are silently ignored. The agent has no way to
understand video content.

### Architecture Question: Plugin Code vs. Skill?

**The keyframe extraction + vision analysis is a strong candidate for a skill**
rather than hardcoded connection logic. The reasons:

- The connection layer's job is receiving the video bytes and making them
  available. The _analysis_ is generic and could be reused across channels
  (WhatsApp, ACP, Matrix).
- A skill approach: connection downloads video → saves to temp file → passes
  file path in the prompt → agent uses a `analyze_video` MCP tool (or the
  skill's prompt instructions tell it to use existing tools).
- Counterargument: skills can't easily inject image content blocks into the
  prompt. The connection layer needs to do the keyframe extraction to get
  images into the vision context.

**Proposed split**:

- **Connection layer**: download video, extract N keyframes via ffmpeg, send
  keyframes as vision content blocks (reuse inbound images infrastructure).
  Extract audio track → transcribe (reuse inbound audio infrastructure).
- **Skill (optional)**: advanced video analysis prompting — "describe scene
  changes", "identify objects across frames", "summarize the narrative arc".
  This is just prompt engineering on top of the keyframes.

### Technical Path

ffmpeg is already installed. The extraction pipeline:

```bash
# Extract 6 evenly-spaced keyframes
ffmpeg -i input.mp4 -vf "select=eq(pict_type\,I)" -frames:v 6 -vsync vfr frame_%03d.jpg

# Or sample at regular intervals (every 5 seconds)
ffmpeg -i input.mp4 -vf "fps=1/5" -frames:v 6 frame_%03d.jpg

# Extract audio track for transcription
ffmpeg -i input.mp4 -vn -acodec libopus output.ogg
```

Claude's vision API can handle multiple images in one prompt. 6 keyframes +
audio transcript gives a solid understanding of most short videos.

### Size Concerns

Videos can be large. Matrix has server-side size limits (typically 50–100 MB),
but even a 30-second phone video can be 20+ MB. Processing should:

- Download to a temp file (don't hold in memory)
- Cap at reasonable duration (5 minutes? configurable)
- Clean up temp files after processing

### Supported Formats

MP4 (H.264), WebM — both handled natively by ffmpeg.

---

## Work Objectives

### Core Objective

When a user sends a video to a Matrix room, the agent sees representative
keyframes (as vision content blocks) and an audio transcript, enabling it to
answer questions about the video.

### Must Have

- `RoomMessageVideo` callback registered in `_register_callbacks()`
- Video bytes downloaded via `client.download()` → temp file
- Keyframe extraction via ffmpeg (configurable count, default 6)
- Keyframes forwarded to agent as image content blocks (reuse inbound images
  path)
- Audio track extraction + transcription (reuse inbound audio backend)
- Duration/size limits (configurable, default: 5 min / 100 MB)
- Temp file cleanup after processing
- Graceful handling: ffmpeg failure → log warning, skip video

### Nice to Have

- Smart keyframe selection (scene changes vs. uniform sampling)
- Video thumbnail sent back to room with "[analyzing video...]" status
- Caching: don't re-extract if the same mxc:// URI was processed before
- Skill for advanced video analysis prompting

### Must NOT Have

- No video generation or editing
- No real-time video streaming analysis
- No video transcoding or re-encoding for output
- No frame-by-frame analysis (keyframes only — cost and context window limits)

---

## Dependency on Inbound Images

This plan depends on matrix-inbound-images being complete. Keyframes are just
images — they flow through the same vision content block pipeline. The audio
transcription reuses the inbound audio backend (if available; optional if not).

---

## Verification Strategy

- Unit test: mock `RoomMessageVideo` event → verify download called, ffmpeg
  invoked, keyframes extracted
- Unit test: ffmpeg failure → warning logged, no crash
- Unit test: video exceeding size limit → rejected with log message
- Integration: send a short video to test room → verify agent describes content
