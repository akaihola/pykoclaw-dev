# Tool-Use Text Concatenation Bug

**Tags:** sdk-consume, streaming, bugfix, mitto, gotcha
**Related:** [result-message-fallback.md], [channel-dispatch.md]

## Problem

When Claude uses tools between text blocks, the streaming path in
`sdk_consume.py` concatenated text from adjacent `AssistantMessage`s
without any separator. Mitto displayed: `"I will do X:Good, now Y:"`

## Root cause

`consume_sdk_response()` forwarded every `TextBlock.text` via `on_text()`
without tracking whether a `ToolUseBlock` appeared in between.  The
non-streaming path (`dispatch.py`) joined with `"\n"` so was less affected.

## Fix

Track `pending_separator` flag.  When an `AssistantMessage` contains both
text and a `ToolUseBlock`, set the flag.  Before emitting the next text
block, emit `"\n\n---\n\n"` (markdown horizontal rule) as a separator.
In Mitto, `<hr/>` triggers coalescing breaks → separate speech bubbles.

Key conditions:
- Only `ToolUseBlock` triggers the separator (not `ThinkingBlock`)
- Only when text was already emitted (`had_text_blocks`)
- Tool-only messages with no text don't trigger it

## Affected file

`pykoclaw/src/pykoclaw/sdk_consume.py`

## Mitto frontend bubble splitting

The `\n\n---\n\n` separator correctly produces `<hr/>` events with distinct
seq numbers in `events.jsonl` (verified). After page reload, the frontend
`coalesceAgentMessages()` correctly splits bubbles at `<hr/>`-only events.
During **live streaming**, however, bubble separation may not occur because
the `shouldAppend` logic in `useWebSocket.js` appends chunks to the last
message before coalescing runs. This is a **Mitto frontend** issue, not a
Pykoclaw issue.

[result-message-fallback.md]: result-message-fallback.md
[channel-dispatch.md]: channel-dispatch.md
