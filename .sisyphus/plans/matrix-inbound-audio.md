# Matrix Inbound Audio Transcription

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: Enable pykoclaw-matrix to receive voice messages and audio
> files, transcribe them via OpenAI Whisper (ChatGPT Plus API), and inject the
> transcript into the agent's message context. Mobile users who send voice notes
> become first-class participants. The transcription backend is pluggable, with
> ChatGPT Plus Whisper as the first supported backend.
>
> **Deliverables**:
>
> - `RoomMessageAudio` event callback in `connection.py`
> - Audio download via `client.download()` from mxc:// URI
> - Pluggable transcription backend interface
> - OpenAI Whisper API backend (first implementation)
> - Transcript injected into XML message context with `type="voice"` attribute
>
> **Estimated Effort**: Medium
> **Depends On**: —

---

## Context

### Current State

Voice messages sent to Matrix rooms are silently ignored. The agent never knows
someone spoke. This is a significant gap for mobile-first users who prefer voice
notes over typing.

### Why This Matters

- Voice notes are extremely common on mobile (Matrix, WhatsApp, etc.)
- Without transcription, the agent is blind to a large class of messages
- The `type="voice"` attribute lets the agent adjust tone — voice messages are
  typically more casual/conversational than typed text
- Transcripts make voice content searchable in the message history

### Technical Path

1. matrix-nio provides `RoomMessageAudio` events with `url` (mxc:// URI) and
   metadata (duration, mimetype — typically OGG/Opus for voice notes)
2. Download audio bytes via `client.download()`
3. Send to transcription backend → get text back
4. Store transcript in `matrix_messages` as a regular message with a voice
   indicator
5. Batch accumulator picks it up like any other message

### Transcription Backend: OpenAI Whisper API

First backend uses the OpenAI API (`POST /v1/audio/transcriptions`):

- Model: `whisper-1`
- Accepts: mp3, mp4, mpeg, mpga, m4a, wav, webm, ogg
- Matrix voice notes are typically OGG/Opus — supported directly
- Requires `OPENAI_API_KEY` (or repurpose existing ChatGPT Plus credentials)
- Cost: ~$0.006/minute of audio — negligible for voice notes

### Backend Interface

```python
class TranscriptionBackend(Protocol):
    async def transcribe(self, audio_data: bytes, mime_type: str) -> str: ...
```

This keeps the door open for local Whisper, Google Speech-to-Text, or other
backends without changing the connection code.

### Key Design Decisions

- **Transcript vs. audio forwarding**: We transcribe and send text, not raw
  audio to Claude. Claude doesn't have native audio input via the SDK path.
- **XML message format**: `<message sender="Alice" time="..." type="voice">
transcribed text here</message>` — the `type="voice"` attribute signals to
  the agent that this was spoken, not typed.
- **Failure mode**: If transcription fails (API down, bad audio), log a warning
  and store a placeholder: "[voice message — transcription failed]". Don't
  silently drop the message.

---

## Work Objectives

### Core Objective

When a user sends a voice message or audio file to a Matrix room, the agent
sees the transcribed text in its message context and can respond naturally.

### Must Have

- `RoomMessageAudio` callback registered in `_register_callbacks()`
- Audio bytes downloaded via `client.download()` from mxc:// URI
- Transcription backend protocol/interface
- OpenAI Whisper API backend implementation
- Transcript stored in `matrix_messages` with voice indicator
- `format_xml_messages` includes `type="voice"` attribute for transcribed
  messages
- Configuration: `PYKOCLAW_MATRIX_TRANSCRIPTION_BACKEND` (default: `openai`)
- Configuration: `OPENAI_API_KEY` for Whisper backend
- Graceful degradation: transcription failure → placeholder text, not crash

### Nice to Have

- Duration metadata in the XML context (`duration="0:42"`)
- Local Whisper backend (via `faster-whisper` or similar) as alternative
- Automatic language detection from Whisper response

### Must NOT Have

- No outbound TTS / audio generation (separate feature)
- No real-time streaming transcription (process complete audio files only)
- No audio storage on disk (transcribe and discard bytes)

---

## Verification Strategy

- Unit test: mock `RoomMessageAudio` event → verify download called,
  transcription backend invoked, transcript stored
- Unit test: transcription failure → placeholder stored, no crash
- Unit test: `format_xml_messages` with voice message → XML has `type="voice"`
- Integration: send voice note to test room → verify agent sees transcript and
  responds
