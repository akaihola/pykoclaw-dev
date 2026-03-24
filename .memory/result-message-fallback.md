# ResultMessage.result text fallback

**Tags:** claude-sdk, agent-core, bugfix, gotcha
**Related:** [channel-dispatch.md], [acp-debugging.md], [agent-output-duplication.md]

## Problem

`query_agent()` only yielded text from `AssistantMessage`/`TextBlock` events.
The `ResultMessage.result` field (which contains the final agent response text)
was silently dropped.

During multi-turn tool-use sessions, sometimes the final text only appears in
`ResultMessage.result` and is NOT re-emitted as a `TextBlock`. This caused
empty replies — the agent DID respond, but the text was lost.

## Fix (2025-02-20)

1. **`agent_core.py`**: Forward `message.result` as `AgentMessage.text` in the
   `"result"` message **only when no text was already collected** via `_on_text`.
2. **`dispatch.py`**: Use `msg.text` from result messages as a **fallback** when
   `text_parts` is empty (avoids duplication when TextBlock streaming works).

## Gotcha: unconditional append causes duplication (fixed 2026-03-24)

The original `_on_result` appended `msg.result` unconditionally. In
`include_partial_messages=False` mode (all Slack/Matrix/WhatsApp dispatches),
`sdk_consume` already forwards the reply via `AssistantMessage` TextBlocks, so
`collected` already holds the text when `_on_result` fires — appending again
doubled every outgoing message. Fixed by guarding with
`had_text = any(m.type == "text" and m.text for m in collected)`.
See [agent-output-duplication.md] for the full investigation.

## Rule

`msg.result` is a **fallback**, not an additional channel. Only use it when
no text has been collected by `_on_text` for this turn.

[channel-dispatch.md]: channel-dispatch.md
[acp-debugging.md]: acp-debugging.md
[agent-output-duplication.md]: agent-output-duplication.md
