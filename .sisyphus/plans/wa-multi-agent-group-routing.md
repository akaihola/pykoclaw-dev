# WhatsApp Multi-Agent Group Routing

## Status: In Progress

## Priority: 2

## TL;DR

> **Quick Summary**: Enable multiple pykoclaw agent instances (Tyko, Ressu, future
> agents) to participate in WhatsApp groups through a single shared WhatsApp
> account. Each group maps to one or more agents. In multi-agent groups, agents
> prefix messages with their identity (`[Ressu]: `, `[Tyko]: `) and follow
> strict turn-taking rules to prevent agent-to-agent loops.
>
> **Estimated Effort**: Medium-Large
> **Depends On**: [wa-ambient-participation.md] (batch/ambient observation model)

---

## Motivation

The user runs multiple pykoclaw instances (agent personalities) on one machine,
all sharing a single WhatsApp account/bridge (run by the pipsa/Ressu instance).
The goal is to have different agents participate in different WhatsApp groups —
some groups with a single agent, others with multiple agents — all through one
WhatsApp number.

## Expected Outcome

- Each WhatsApp group can be mapped to one or more pykoclaw agent instances
- Agents in the same group prefix outgoing messages with `[AgentName]: `
- Agents only respond when addressed (by name or context)
- Agents never respond to another agent's message unless a human explicitly
  redirects the conversation
- Scheduled task delivery (e.g., Tyko's Willison blog summaries) routes to the
  correct group

## Design Decisions (Resolved)

### Single process (Option 3)

One pykoclaw-whatsapp instance handles all agent personalities. This avoids
IPC, shared DB polling, and distributed state. The neonize bridge is the single
point of connection; dispatch fans out to multiple agents within the same process.

### JSON routing config

A JSON file referenced by `PYKOCLAW_WA_AGENT_ROUTES` env var:

```json
{
  "default_agent": "Ressu",
  "agents": {
    "Ressu": {},
    "Tyko": { "model": "claude-opus-4-6" }
  },
  "routes": {
    "120363...@g.us": ["Ressu"],
    "120364...@g.us": ["Tyko"],
    "120365...@g.us": ["Ressu", "Tyko"]
  }
}
```

Without this file, the system behaves exactly as before (single agent from
`PYKOCLAW_WA_TRIGGER_NAME`).

### Sequential dispatch

When multiple agents are mapped to a group, they process the batch one at a
time. Simpler than parallel, avoids resource contention.

### Conversation namespace

Format: `wa-{agent_name_lower}-{jid}`. Each agent gets its own conversation,
session, and working directory. No migration needed — losing old session
history is acceptable.

## Implementation Progress

### ✅ Phase 1: Core routing (DONE)

- `routing.py` — `RoutingConfig`, `AgentConfig`, `load_routing_config()`
- `config.py` — `PYKOCLAW_WA_AGENT_ROUTES` setting
- `handler.py` — `trigger_names` (plural), `find_hard_mentions()` for multi-name
  detection
- `connection.py` — per-agent dispatch, `[AgentName]:` prefixing in multi-agent
  groups, multi-agent-aware system prompts, delivery queue routing with agent
  name parsing
- `__init__.py` — load & display routing config on startup
- 102 tests passing (21 new tests for routing + multi-agent behavior)

### 🔲 Phase 2: Deployment & integration testing

- Create the actual `agent-routes.json` for the production instance
- Update the systemd service with `PYKOCLAW_WA_AGENT_ROUTES` env var
- End-to-end test with real WhatsApp groups
- Verify delivery queue routing works with the new conversation format

### 🔲 Phase 3: Documentation

- Update pykoclaw-whatsapp README with multi-agent setup instructions
- Add example `agent-routes.json`

## Related

- [wa-ambient-participation.md] — Prerequisite: ambient observation model
  (batch accumulation, LLM-driven reply decisions, session resumption)
- [scheduled-task-delivery.md] — Delivery queue for task results to channels

[wa-ambient-participation.md]: wa-ambient-participation.md
[scheduled-task-delivery.md]: scheduled-task-delivery.md
