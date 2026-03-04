# Hard-Mention Reply Fallback (Plan A + B)

## Status: In Progress
## Priority: 1

## TL;DR

> **Quick Summary**: When the agent is directly addressed (hard mention) but
> produces a response without `<reply>` tags, the message is silently dropped
> ("Agent chose silence"). This plan fixes that with two complementary layers:
>
> - **Plan A** — Runtime fallback: after `_extract_reply()` returns None for a
>   hard-mention, take the last `\n\n---\n\n`-separated segment of `full_text`
>   and send it as the reply, logging a warning. Scoped exclusively to
>   hard-mention dispatches to avoid leaking group-channel tool reasoning.
>
> - **Plan B** — Prompt reinforcement: extend the hard-mention directive to
>   explicitly tell the model that *any* response to the user — including
>   "I couldn't find X" or "I don't know" — must be wrapped in `<reply>` tags.
>
> **Incident that motivated this**: 2026-03-04, session 8223bf7c, DM channel
> D0AK314Q5EC. User sent "Analysoi kaikki näiden kuvien teksti tarkasti
> Geminillä…" (with image attachments). Images failed to download due to Slack
> cross-domain auth stripping. Agent responded correctly ("En löydä kuvia
> tästä kanavasta tänään…") but without `<reply>` tags. Result: "Agent chose
> silence." User received nothing.
>
> **Deliverables**:
> - Updated `_handle_agent_trigger()` in `pykoclaw-slack/connection.py` (Plan A)
> - Updated `_build_system_prompt()` / hard-mention prompt part (Plan B)
> - Failing → passing tests for both plans
> - Updated `.memory/` files and CLAUDE.md
>
> **Estimated Effort**: Quick (< 1 hour)
> **Depends On**: nothing
> **Parallel Execution**: NO — single file change + tests

---

## Context

The `_extract_reply()` function in `pykoclaw-slack` uses an allowlist: only
text inside `<reply>…</reply>` tags reaches the user. This is correct for
group channels where the model is an ambient observer and most responses are
tool-use with no visible reply. However in DM / hard-mention contexts the
model is required to respond, and when it forgets the tag (or the instruction
wasn't followed) the user gets silence.

The existing unclosed-tag fallback (added 2026-03-04) handles one failure
pattern: agent opens `<reply>` before tool calls but never closes it. The
new fallback handles the orthogonal pattern: agent produces clean text but
no `<reply>` marker at all.

### Why Plan A is safe for group channels

The fallback is gated on `hard_mention=True`. Group-channel soft-mention
dispatches never set this flag, so their existing silence-by-default behaviour
is fully preserved.

### Why the `---` split is necessary

`consume_sdk_response` joins multi-turn text with `\n\n---\n\n`. A typical
tool-use session might produce:

```
Let me search for those files...

---

Nothing found there, checking elsewhere...

---

I couldn't find any images in the attachment directory.
```

Taking the *last* segment avoids sending intermediate tool reasoning to the
user. If there are no `---` separators (single-turn response), the whole
`full_text` is used.

---

## Implementation Plan

### 1. Plan B — Prompt (no test infra needed, low risk first)

In `_build_system_prompt` / `_handle_agent_trigger`, change the hard-mention
directive from:

```python
"You were directly addressed — you MUST reply using `<reply>` tags."
```

to:

```python
"You were directly addressed — you MUST reply using `<reply>` tags. "
"This applies to ALL responses including 'I cannot find X', "
"'I don't know', or any other message to the user."
```

### 2. Plan A — Fallback extraction (new tests required)

After:
```python
extracted = _extract_reply(result.full_text)
```

Add:
```python
if extracted is None and hard_mention and result.full_text.strip():
    segments = [s.strip() for s in result.full_text.split("\n\n---\n\n") if s.strip()]
    candidate = segments[-1] if segments else result.full_text.strip()
    if candidate:
        log.warning(
            "Hard mention produced text without <reply> tags for %s "
            "— falling back to raw last segment (%d chars)",
            effective_channel_id,
            len(candidate),
        )
        extracted = candidate
```

### 3. Tests

New test module: `pykoclaw-slack/tests/test_hard_mention_fallback.py`

Test cases:
- `test_plan_a_plain_text_hard_mention` — no tags, hard mention → sends text
- `test_plan_a_multi_turn_takes_last_segment` — `---`-separated turns, hard mention → last segment only
- `test_plan_a_soft_mention_stays_silent` — no tags, soft mention → None (no change)
- `test_plan_a_empty_text_stays_silent` — empty full_text → None
- `test_plan_a_multi_turn_all_empty_segments_stays_silent` — all segments whitespace → None
- `test_plan_b_prompt_contains_error_message_instruction` — system prompt check

### 4. Documentation

- `.memory/hard-mention-reply-fallback.md` — new memory file
- `.memory/INDEX.md` — add entry
- `CLAUDE.md` — update "Session resume has TWO failure modes" section to mention this third mode
