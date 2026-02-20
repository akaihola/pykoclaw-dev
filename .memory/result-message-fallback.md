# ResultMessage.result text fallback

**Tags:** claude-sdk, agent-core, bugfix, gotcha
**Related:** [channel-dispatch.md], [acp-debugging.md]

## Problem

`query_agent()` only yielded text from `AssistantMessage`/`TextBlock` events.
The `ResultMessage.result` field (which contains the final agent response text)
was silently dropped.

During multi-turn tool-use sessions, sometimes the final text only appears in
`ResultMessage.result` and is NOT re-emitted as a `TextBlock`. This caused
empty replies — the agent DID respond, but the text was lost.

## Fix (2025-02-20)

1. **`agent_core.py`**: Forward `message.result` as `AgentMessage.text` in the
   `"result"` message.
2. **`dispatch.py`**: Use `msg.text` from result messages as a **fallback** when
   `text_parts` is empty (avoids duplication when TextBlock streaming works).

## Rule

Always consume ALL text fields from SDK message types. Don't assume one message
type is the sole carrier of response text.

[channel-dispatch.md]: channel-dispatch.md
[acp-debugging.md]: acp-debugging.md
