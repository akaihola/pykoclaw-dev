# WhatsApp Multi-Agent Routing

**Tags:** whatsapp, routing, multi-agent, architecture
**Related:** [threading-model.md], [channel-dispatch.md]

A single WhatsApp account serves multiple agent personalities via
`RoutingConfig` (JSON file → `PYKOCLAW_WA_AGENT_ROUTES`).

**Key design points:**

- `RoutingConfig` maps group JIDs → agent name(s); unrouted chats use
  `default_agent`.
- Each agent with a `data_dir` gets its own SQLite DB (conversations,
  sessions, scheduled tasks). The bridge DB (`wa_messages`, `wa_chats`)
  is shared.
- Conversation names include the agent: `wa-{agent}-{jid}`.
- Multi-agent groups get `[AgentName]: ` message prefixing and loop
  prevention via system prompt ("never respond to another agent").
- Hard mentions (`@Tyko`) only force that specific agent to reply.
- Delivery polling iterates all agent DBs (bridge + per-agent) so
  per-agent schedulers' results are delivered.
- Without `PYKOCLAW_WA_AGENT_ROUTES`, single-agent mode is preserved
  exactly as before.

[threading-model.md]: threading-model.md
[channel-dispatch.md]: channel-dispatch.md
