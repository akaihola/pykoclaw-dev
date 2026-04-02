# Streaming Responses in Mitto

## Status: Done
## Completed: 2026-03-01
## Priority: 3

## TL;DR

> **Quick Summary**: Enable token-level incremental response display in Mitto by
> opting in to the Claude Agent SDK's `include_partial_messages` streaming mode.
> Currently `receive_response()` only yields complete `AssistantMessage` objects
> because the flag defaults to `False`. The entire downstream pipeline (worker
> protocol, ACP server, Mitto MarkdownBuffer) is already built for incremental
> chunks — only `sdk_consume.py` and the options construction need changes.
>
> **Estimated Effort**: Quick (< 2 hours)
> **Depends On**: (none)

---

## Motivation

Users see the full response appear all at once in Mitto. Despite the architecture
being streaming-native end-to-end (`TextChunkMessage` protocol, `on_text`
callbacks, ACP `session/update` notifications, Mitto's `MarkdownBuffer`), the
Claude Agent SDK's `include_partial_messages` flag is `False` by default. This
means `receive_response()` only yields complete `AssistantMessage` objects with
full text blocks, so the entire downstream streaming infrastructure receives one
large chunk instead of incremental tokens.

## Expected Outcome

Text appears progressively in the Mitto web UI as Claude generates it, similar to
the ChatGPT / claude.ai streaming experience.

## Implementation

### 1. Enable SDK streaming

In `agent_core.py` (or wherever `ClaudeAgentOptions` is constructed), set:

```python
ClaudeAgentOptions(include_partial_messages=True)
```

### 2. Handle `StreamEvent` in `sdk_consume.py`

The SDK yields `StreamEvent` objects alongside complete messages when streaming is
enabled. Extract text deltas:

```python
from claude_agent_sdk import StreamEvent

async for message in client.receive_response():
    if isinstance(message, StreamEvent):
        event = message.event
        if event.get("type") == "content_block_delta":
            delta = event.get("delta", {})
            if delta.get("type") == "text_delta":
                await on_text(delta["text"])
    elif isinstance(message, AssistantMessage):
        # Still emitted — suppress redundant on_text to avoid double-sending
        ...
```

### 3. Avoid double-emission

With `include_partial_messages=True`, both `StreamEvent` deltas and complete
`AssistantMessage` blocks arrive. The current `sdk_consume.py` calls
`on_text(block.text)` for each `TextBlock` in `AssistantMessage`. Once deltas
drive `on_text`, skip the `TextBlock`-level call to avoid sending the text twice.

### 4. Verify downstream (no changes expected)

Everything below `sdk_consume.py` should work as-is:

- `worker.py` — `TextChunkMessage` already handles small chunks
- `worker_pool.py` — reads chunks line-by-line from worker stdout
- `server.py` — sends `session/update` with `agent_message_chunk` per chunk
- Mitto `MarkdownBuffer` — designed for small incremental chunks (200ms soft
  flush, block-boundary detection)

## Key Files

- `pykoclaw/src/pykoclaw/sdk_consume.py` — SDK response iteration + `on_text`
- `pykoclaw/src/pykoclaw/agent_core.py` — `ClaudeAgentOptions` construction
- `pykoclaw-acp/src/pykoclaw_acp/worker.py` — subprocess `on_text` → `TextChunkMessage`
- `pykoclaw-acp/src/pykoclaw_acp/server.py` — ACP `session/update` notifications

## Technical Notes

- The Claude Agent SDK (v0.1.39) exposes `StreamEvent` in the `Message` union
  type, gated by `include_partial_messages=True` on `ClaudeAgentOptions`.
- `StreamEvent.event` is untyped (`dict[str, Any]`) — inspect
  `event["type"]` and `event["delta"]` at runtime.
- Mitto's `MarkdownBuffer` has a 200ms soft flush timeout that coalesces rapid
  chunks — this is desirable for token-rate streaming to avoid excessive
  re-renders.
