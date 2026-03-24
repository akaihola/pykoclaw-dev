# Slack Reply Extraction — `<reply>` Tag Failures

**Tags:** slack, reply-extraction, gotcha, bugfix, tool-use, hard-mention
**Related:** [slack-plugin-gotchas.md], [tool-use-text-concatenation.md], [session-resume-system-prompt.md]

Two known failure modes where `_extract_reply` returns `None` despite the
agent having produced a valid response.

---

## Failure mode 1 — Unclosed `<reply>` tag (session a01cdfa4, 2026-03-04)

Agent opens `<reply>` in the first text block before tool calls, never
emits `</reply>`. `re.findall(r"<reply>(.*?)</reply>", ...)` matches nothing.

**Fix:** after the complete-pair search, grab everything after the last
`<reply>` when `</reply>` is entirely absent:

```python
if "<reply>" in text and "</reply>" not in text:
    m = re.search(r"<reply>(.*)", text, re.DOTALL)
    if m and (tail := m.group(1).strip()):
        return tail
```

---

## Failure mode 2 — No `<reply>` tag at all on hard mention (session 8223bf7c, 2026-03-04)

Agent produces a valid response ("En löydä kuvia tästä kanavasta tänään…")
without any `<reply>` marker. `_extract_reply` returns `None` correctly —
but the response should still be delivered in a hard-mention (DM/direct
address) context.

**Fix (Plan A):** `_handle_agent_trigger` falls back to
`_extract_hard_mention_fallback(full_text)` when `hard_mention=True`:
takes the last `\n\n---\n\n`-separated segment (the final text turn), logs
a WARNING, and delivers it. Group channels are unaffected (fallback only
fires on `hard_mention=True`).

**Fix (Plan B):** `_build_hard_mention_directive()` returns a strengthened
prompt that explicitly covers error/inability responses:

> "…This applies to ALL responses including 'I cannot find X', 'I don't
> know', or any other message to the user."

---

## Failure mode 3 — Plan A fallback fires after MCP tool already sent (suspected)

When the agent uses `mcp__slack__send_slack_message` directly in a turn AND
produces text without `<reply>` tags, Plan A (`_extract_hard_mention_fallback`)
fires on hard-mention dispatches and sends the same content a second time.
Result: two Slack messages for one agent turn — the tool send and the fallback
send. See
[pykoclaw-slack/backlog/001-duplicate-slack-responses.md](../pykoclaw-slack/backlog/001-duplicate-slack-responses.md)
for the full investigation (H1).

## Diagnosis

Use `analyze-session.py --mode transcript` from the `claude-session-logs`
skill. Search for `<reply>` in assistant turns. If absent entirely,
check `hard_mention` status from the log line that triggered the dispatch.

[slack-plugin-gotchas.md]: slack-plugin-gotchas.md
[tool-use-text-concatenation.md]: tool-use-text-concatenation.md
[session-resume-system-prompt.md]: session-resume-system-prompt.md
