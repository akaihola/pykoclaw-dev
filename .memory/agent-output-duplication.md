# Agent Output Duplication — \_on_result Unconditional Append

**Tags:** agent-core, slack, bugfix, gotcha, regression
**Related:** [result-message-fallback.md], [slack-reply-extraction.md], [channel-dispatch.md]

## Symptom

Every Slack (and potentially Matrix/WhatsApp) outgoing message body was
duplicated: the same text appeared twice inside a single stored DB row and was
sent as a single doubled Slack message. Confirmed from Slack DM D0AK314Q5EC
thread 1774354618.924119, DB rows 606/607/609 in `~/coleaders/pykoclaw.db`
(2026-03-24).

## Root cause

`agent_core._on_result` unconditionally appended `msg.result` as a
`type="text"` `AgentMessage`, even when the text was already in `collected`
via `_on_text` from `AssistantMessage` TextBlocks.

In `include_partial_messages=False` mode (used by ALL channel plugins), the
non-streaming path of `sdk_consume` forwards TextBlocks via `on_text`. So by
the time `_on_result` fires, `collected` already holds the reply. Appending
`msg.result` again concatenated the text twice in `full_text`.

`dispatch.py` had a guard `if msg.text and not text_parts` at the
`type="result"` yield, but `agent_core._on_result` bypassed it by wrapping
`msg.result` as `type="text"` instead — so that guard never fired.

## Fix (2026-03-24, pykoclaw commit b2b89ad)

Added `had_text` check in `_on_result`:

```python
had_text = any(m.type == "text" and m.text for m in collected)
if msg.result and not had_text:
    collected.append(AgentMessage(type="text", text=msg.result, is_final=True))
```

## Regression tests

- `pykoclaw/tests/test_agent_core.py::test_query_agent_does_not_duplicate_text_when_result_matches_text_blocks`
- `pykoclaw-slack/tests/test_duplicate_slack_messages_regression.py`

[result-message-fallback.md]: result-message-fallback.md
[slack-reply-extraction.md]: slack-reply-extraction.md
[channel-dispatch.md]: channel-dispatch.md
