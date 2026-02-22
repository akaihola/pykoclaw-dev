# Claude Code SDK: system_prompt Ignored on Session Resume

**Tags:** claude-sdk, gotcha, session-resume, channel-plugins, matrix
**Related:** [session-resume-retry.md], [channel-dispatch.md]

`ClaudeAgentOptions.system_prompt` is **baked into the session at creation
time**. When resuming a session (`resume=session_id`), the `system_prompt`
parameter is silently ignored — the agent uses the original session's
system prompt.

**Consequence:** Any per-message dynamic content in the system prompt
(e.g. "you MUST reply because you were hard-mentioned") will never be
seen by the agent on resumed sessions.

**Fix pattern:** Put dynamic, per-turn instructions in the **user prompt**
(the `prompt` argument to `dispatch_to_agent()`), not in `system_prompt`.
Reserve `system_prompt` for static instructions that don't change between
turns.

**Example (Matrix hard-mention):**

```python
# BAD — invisible on session resume:
if hard_mention:
    system_prompt += "\nYou MUST reply."

# GOOD — always visible:
if hard_mention:
    prompt += "\n\nYou were directly addressed — you MUST reply."
```

**Discovered:** 2026-02-22 — Tyko chose silence in a Matrix group chat
despite a hard mention because the "MUST reply" instruction was only in
the system prompt, and the session was being resumed from an earlier turn.

[session-resume-retry.md]: session-resume-retry.md
[channel-dispatch.md]: channel-dispatch.md
