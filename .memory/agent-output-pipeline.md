# Agent Output Pipelines: Fresh Session + System Prompt Required

**Tags:** dispatch, gotcha, channel-plugins, send-command, session-resume
**Related:** [session-resume-system-prompt.md], [channel-dispatch.md]

When agent output flows somewhere other than back to the invoker (e.g. a
CLI command that delivers the reply to a Matrix room), two things are
required:

1. **`fresh=True`** — never resume an existing session. The old session's
   baked-in system prompt (e.g. ambient "be silent, use `<reply>` tags")
   will produce garbage in a different context.

2. **A role-explaining system prompt** — the agent must know its output IS
   the delivery mechanism. Without it, a fresh-session agent acts as a
   generic assistant and tells the user to send the message themselves.

**Three-iteration pattern discovered the hard way:**

| Attempt                    | Problem                       | Root cause                          |
| -------------------------- | ----------------------------- | ----------------------------------- |
| 1. Resumed session         | 3 messages of meta-commentary | Ambient system prompt leaked        |
| 2. Fresh, no system prompt | "I can't send messages"       | Agent didn't know output = delivery |
| 3. Fresh + system prompt   | Clean, direct response ✓      | Agent understood its role           |

**Rule:** When building any feature where agent output is piped to a
channel, always start with `fresh=True` + a system prompt explaining the
delivery mechanism. Don't assume a plumbing test validates content quality.

**The `send` command's system prompt:**

```
You are a helpful assistant. Your entire response will be delivered as a
message to a chat conversation. Write your reply as if you are speaking
directly to the recipient. Do not include meta-commentary about sending
or delivering the message — just respond with the content itself.
```

**Discovered:** 2026-02-22 — building `pykoclaw send` CLI command.

[session-resume-system-prompt.md]: session-resume-system-prompt.md
[channel-dispatch.md]: channel-dispatch.md
