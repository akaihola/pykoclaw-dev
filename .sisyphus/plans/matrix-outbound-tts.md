# Matrix Outbound TTS Audio

## Status: Backlog

## Priority: 3

## TL;DR

> **Quick Summary**: Give the agent the ability to send voice messages to Matrix
> rooms via text-to-speech. Needs high-quality Finnish AND English — ruling out
> most options. The pluggable backend design mirrors the inbound audio
> transcription plan. First backend: OpenAI `gpt-4o-mini-tts`.
>
> **Deliverables**:
>
> - `_send_audio(room_id, data, filename, content_type, duration)` method
> - Pluggable TTS backend interface
> - OpenAI `gpt-4o-mini-tts` backend (first implementation)
> - MCP tool `send_voice_reply` or automatic TTS toggle per-room
>
> **Estimated Effort**: Medium
> **Depends On**: —

---

## Context

### Current State

The agent can only reply with text and images. For accessibility, mobile users,
or "read me this while I cook" scenarios, voice output would be valuable.

### Use Cases

- Language learning: "pronounce this Finnish word"
- Accessibility: visually impaired users get spoken responses
- Convenience: "read me this summary" while doing something else
- Natural voice conversations: paired with inbound audio transcription, the
  agent becomes a voice-native participant

### TTS Provider Research (Feb 2026)

**Finnish + English quality is the hard constraint.** Most TTS engines optimize
for English; Finnish is an afterthought with accents and mispronunciations.

#### Claude Max — No TTS API

Anthropic has no developer-accessible TTS API. Claude's mobile/web voice mode
uses ElevenLabs and Hume AI internally, but these are not exposed to developers.
**Not an option.**

#### ChatGPT Plus — Separate API billing

ChatGPT Plus ($20/mo) does NOT include OpenAI API access. TTS requires separate
pay-as-you-go billing. However, the API is available and the cost is low.

#### Provider comparison for Finnish + English

| Provider                     | Finnish quality                  | English quality | Latency         | Cost                     | Notes                                                                                      |
| ---------------------------- | -------------------------------- | --------------- | --------------- | ------------------------ | ------------------------------------------------------------------------------------------ |
| **OpenAI `gpt-4o-mini-tts`** | Good (35% lower WER vs prior)    | Excellent       | Fast            | ~$0.015/min              | Best value. 13 voices, multilingual auto-detect. Dec 2025 version prioritizes reliability. |
| **ElevenLabs v3**            | Excellent (explicitly optimized) | Excellent       | Medium (non-RT) | ~$0.99/unit (expensive)  | Gold standard for expressiveness. Audio tags for emotion. 4000+ voices.                    |
| **ElevenLabs Flash v2.5**    | Good                             | Excellent       | Low             | ~$0.99/unit              | Better for real-time than v3.                                                              |
| **Azure AI Speech**          | Very good (4.2/5 naturalness)    | Excellent       | Low             | Usage-based, free tier   | Broadest multilingual coverage. Enterprise-grade.                                          |
| **Google Cloud TTS**         | Good (Neural2/WaveNet)           | Excellent       | Low             | Per-character, free tier | 300+ voices. Good if already in GCP.                                                       |
| **OpenAI `tts-1-hd`**        | Decent                           | Very good       | Slow            | ~$0.030/min              | Older model. Better clarity but slower, 2x cost.                                           |

#### Recommendation: OpenAI `gpt-4o-mini-tts` as first backend

- **Why**: Best cost/quality ratio. Finnish is supported with 35% WER improvement
  over prior models. $0.015/min is negligible for agent voice replies (typically
  10–30 seconds). Fast generation. Simple REST API.
- **Tradeoff**: Not the absolute best Finnish quality (ElevenLabs wins there) but
  good enough for an agent voice reply, and 60x cheaper.
- **Upgrade path**: The pluggable backend interface means switching to ElevenLabs
  or Azure later is just a config change.

### Matrix `m.audio` Event

```json
{
  "msgtype": "m.audio",
  "body": "voice-reply.ogg",
  "url": "mxc://...",
  "info": {
    "mimetype": "audio/ogg",
    "duration": 12000,
    "size": 48000
  }
}
```

Element renders this as an inline audio player with play/pause and duration.
OGG/Opus is the standard format for Matrix voice messages.

### Output Format

OpenAI TTS outputs mp3, opus, aac, flac, wav, or pcm. **Use opus** — it's the
Matrix voice message standard, small file size, and Element plays it natively
as a voice message (with waveform UI).

---

## Work Objectives

### Core Objective

The agent can speak its replies as voice messages in Matrix rooms, with
high-quality Finnish and English synthesis.

### Must Have

- `_send_audio(room_id, data, filename, content_type, duration)` method in
  `connection.py`, parallel to `_send_image`
- Upload audio via `client.upload()` → send as `m.audio` event
- TTS backend protocol:
  ```python
  class TTSBackend(Protocol):
      async def synthesize(self, text: str, voice: str | None = None) -> tuple[bytes, str, int]:
          """Returns (audio_bytes, mime_type, duration_ms)."""
          ...
  ```
- OpenAI `gpt-4o-mini-tts` backend implementation (opus output)
- MCP tool `send_voice_reply` for explicit voice responses
- Configuration: `PYKOCLAW_MATRIX_TTS_BACKEND` (default: `openai`)
- Configuration: `PYKOCLAW_MATRIX_TTS_VOICE` (default: `nova` — works well
  for both English and Finnish)
- Graceful degradation: TTS failure → fall back to text reply, log warning

### Nice to Have

- Per-room voice toggle ("always reply with voice in this room")
- ElevenLabs backend as premium alternative
- Voice selection per language (detect Finnish → use Finnish-optimized voice)
- Automatic language detection to pick optimal voice

### Must NOT Have

- No real-time streaming audio (generate complete audio, then send)
- No voice cloning or custom voice training
- No inbound audio handling (separate plan: matrix-inbound-audio)

---

## Verification Strategy

- Unit test: mock TTS backend → verify `_send_audio` calls `room_send` with
  correct `m.audio` event structure
- Unit test: TTS failure → text fallback delivered, warning logged
- Unit test: MCP tool calls TTS backend and triggers `_send_audio`
- Integration: trigger voice reply in test room → verify Element shows audio
  player
