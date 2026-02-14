# Channel Dispatch Pattern

**Tags:** messaging, architecture
**Related:** [plugin-system.md], [threading-model.md]

Channel plugins (WhatsApp, ACP, future Telegram) share the same flow via
`pykoclaw-messaging`:

```
channel receives message
  → dispatch_to_agent(prompt, channel_prefix, channel_id, db, ...)
    → lookup/create conversation named "{prefix}-{id}"
    → call query_agent() with optional session resumption
    → stream text chunks via on_text callback
    → return DispatchResult(full_text, session_id)
```

The `channel_prefix` convention (`wa-`, `acp-`, `tg-`) keeps conversations
namespaced per channel. The `on_text` callback enables real-time streaming to
each channel's transport (stdout JSON-RPC for ACP, WhatsApp API for WA).

[plugin-system.md]: plugin-system.md
[threading-model.md]: threading-model.md
