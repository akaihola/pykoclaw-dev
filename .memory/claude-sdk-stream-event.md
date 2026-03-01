# Claude Agent SDK: StreamEvent and include_partial_messages

**Tags:** claude-sdk, streaming, sdk-consume, gotcha
**Related:** [tool-use-text-concatenation.md]

## Enabling token streaming

Set `include_partial_messages=True` on `ClaudeAgentOptions`. This makes
`receive_response()` yield `StreamEvent` objects interleaved with the usual
`AssistantMessage` and `ResultMessage` objects.

## StreamEvent import

`StreamEvent` is **not** in the top-level `claude_agent_sdk` namespace — it
lives in `claude_agent_sdk.types`:

```python
from claude_agent_sdk.types import StreamEvent   # correct
from claude_agent_sdk import StreamEvent          # ImportError / missing
```

Verified in SDK v0.1.35.

## Double-emission trap

With `include_partial_messages=True` the SDK emits **both**:

- `StreamEvent` with `content_block_delta` / `text_delta` — incremental tokens
- `AssistantMessage` with complete `TextBlock` — the full final text

If `on_text` is called for both, the text appears twice. The fix (in
`sdk_consume.py`): set a `streaming_active` flag when any `text_delta` is
emitted, and skip `TextBlock` processing in the matching `AssistantMessage`.

## Relevant stream event sequence

```
content_block_start  → index, content_block.type = "text" or "tool_use"
content_block_delta  → index, delta.type = "text_delta", delta.text = "..."
content_block_stop   → index
message_stop
```

Track active text block indices via `content_block_start` / `content_block_stop`
so that deltas for non-text blocks (e.g. thinking) are ignored.

[tool-use-text-concatenation.md]: tool-use-text-concatenation.md
