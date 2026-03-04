# Slack Reply Extraction — Unclosed `<reply>` Tag

**Tags:** slack, reply-extraction, gotcha, bugfix, tool-use
**Related:** [slack-plugin-gotchas.md], [tool-use-text-concatenation.md], [session-resume-system-prompt.md]

## The bug (2026-03-04, session a01cdfa4)

`_extract_reply` in `connection.py` used `re.findall(r"<reply>(.*?)</reply>", ...)`.
When the agent opens `<reply>` in its **first text block before tool calls** and
never emits `</reply>`, the regex finds nothing and returns `None`.
SlackConnection logs "Agent chose silence" and sends nothing to Slack.

## How it happens

`sdk_consume.py` joins multi-turn text with `\n\n---\n\n` separators, so
`full_text` looks like:

```
<reply>Yritän uudelleen…

---

Löysin 14 kuvaa…

---

Löysin QR-koodit kuvista… [actual answer]
```

The `<reply>` from turn 1 is never closed; the final answer is outside any tag.

## The fix (pykoclaw-slack `0d7cfd9`)

After the complete-pair search, fall back to grabbing everything after the
last `<reply>` when `</reply>` is entirely absent:

```python
if "<reply>" in text and "</reply>" not in text:
    m = re.search(r"<reply>(.*)", text, re.DOTALL)
    if m:
        tail = m.group(1).strip()
        if tail:
            return tail
```

The `"</reply>" not in text` guard ensures empty `<reply></reply>` pairs
(which correctly return `None`) are not accidentally matched by the fallback.

## Diagnosis

Use `analyze-session.py --mode transcript` from the `claude-session-logs`
skill. Look for `<reply>` in early assistant turns followed by tool calls,
with no matching `</reply>` anywhere in the output.

[slack-plugin-gotchas.md]: slack-plugin-gotchas.md
[tool-use-text-concatenation.md]: tool-use-text-concatenation.md
[session-resume-system-prompt.md]: session-resume-system-prompt.md
