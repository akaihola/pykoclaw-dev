# Channel Dispatch Pattern

**Tags:** messaging, architecture
**Related:** [plugin-system.md], [threading-model.md]

Channel plugins (WhatsApp, Slack, Matrix, ACP, future Telegram) share the same
flow via `pykoclaw-messaging`:

```
channel receives message
  → dispatch_to_agent(prompt, channel_prefix, channel_id, db, ...)
    → lookup/create conversation named "{prefix}-{id}"
    → call query_agent() with optional session resumption
    → optionally stream text chunks via on_text callback
    → return DispatchResult(full_text, session_id)
```

The `channel_prefix` convention keeps conversations namespaced per channel.
WhatsApp uses `wa-{agent_name}-` (e.g. `wa-ressu-`) to support multi-agent
routing; other channels use simple prefixes (`matrix-`, `slack-`, `acp-`,
`tg-`).

## Streaming vs. non-streaming

`dispatch_to_agent()` accepts `include_partial_messages: bool = True` which is
forwarded to `query_agent()` → `ClaudeAgentOptions`. Channels that don't
stream tokens incrementally should pass `False` to avoid the overhead of
receiving streaming deltas from the API:

| Channel       | include_partial_messages | on_text                     |
| ------------- | ------------------------ | --------------------------- |
| ACP (Mitto)   | True (default, own loop) | yes — drives session/update |
| pykoclaw-chat | True (default)           | yes — terminal echo         |
| Slack         | **False**                | no                          |
| WhatsApp      | **False**                | no                          |
| Matrix        | **False**                | no                          |

[plugin-system.md]: plugin-system.md
[threading-model.md]: threading-model.md
