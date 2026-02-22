# WhatsApp Multi-Agent Group Routing

## Status: Done
## Completed: 2026-02-22

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

## WhatsApp Group Architecture

| Group           | Members         | Behavior                                          |
| --------------- | --------------- | ------------------------------------------------- |
| **Pipsa**       | User + Ressu    | Ressu responds directly (existing)                |
| **Tyko**        | User + Tyko     | Tyko delivers summaries + responds directly       |
| **Mixed**       | User + Ressu + Tyko | Both follow, respond when addressed, prefix msgs |
| **Family**      | Family + TBD    | Future — family group with one or more agents     |

## Design Decisions

### Single WhatsApp bridge (Ressu/pipsa owns the connection)

Only the pipsa instance runs the WhatsApp bridge (neonize). Other instances
(Tyko, etc.) do not connect to WhatsApp directly. Message routing must happen
within or between pykoclaw instances via the shared infrastructure.

### Group → agent routing table

A configuration mapping each WhatsApp group JID to one or more agent identities.
Could live in:
- pykoclaw config (env vars / settings)
- SQLite database
- A config file shared between instances

**Open question**: How do non-bridge instances (Tyko) receive messages and send
replies? Options:
1. **Shared DB polling**: All instances read from the same WhatsApp message DB;
   the bridge instance sends on behalf of others
2. **Internal IPC**: Bridge instance dispatches to other instances via HTTP/unix
   socket
3. **Single process, multiple agent configs**: One pykoclaw-whatsapp instance
   handles all groups, dispatching to different agent personalities based on
   group mapping

### Message identity prefixing

In multi-agent groups, every outgoing message is prefixed:
```
[Ressu]: Here's what I think about that...
[Tyko]: The latest from Simon Willison's blog...
```

This is applied at the WhatsApp send layer, not by the LLM (to prevent the
agent from "forgetting" the prefix).

### Agent-to-agent loop prevention

Rules for multi-agent groups:
1. Each agent observes all messages (via ambient participation / batch model)
2. Agents recognize messages from other agents by the `[AgentName]: ` prefix
3. An agent MUST NOT reply to another agent's message — even if addressed
4. Only after a **human participant** sends a message can agents respond again
5. The system prompt includes: "Messages prefixed with `[Name]:` are from
   another AI agent in this group. Do NOT respond to them. Wait for a human
   message before considering whether to speak."

### Scheduled task delivery to groups

When a scheduled task (e.g., Willison blog summary) targets a WhatsApp group,
the delivery queue routes it to the correct group JID. The bridge instance
sends the message with the appropriate agent prefix.

## Implementation Sketch

### 1. Group-to-agent routing config

```python
# Possible config structure
class GroupAgentMapping(BaseModel):
    group_jid: str
    agent_name: str          # Display name for prefixing
    agent_instance: str      # Which pykoclaw instance handles this agent
    is_primary: bool = True  # Primary agent responds by default
```

### 2. Message dispatch changes

- `on_message`: After receiving a message, check group JID against routing table
- If group maps to multiple agents → dispatch to each mapped agent instance
- Each agent's system prompt includes multi-agent awareness instructions

### 3. Outgoing message prefixing

- Before `OutgoingQueue.send()`, prepend `[AgentName]: ` to message text
- Only apply in groups with multiple mapped agents (single-agent groups
  don't need prefixing)

### 4. Cross-instance communication

**TBD** — this is the hardest architectural question. The bridge instance needs
to either:
- Forward messages to other pykoclaw instances for processing
- Handle all agent personalities itself (simpler but less modular)
- Use the delivery queue as a shared mailbox

## Resolved Questions

1. **Single-process, multiple agent configs** was chosen. One `pykoclaw whatsapp
   run` process handles all agent personalities, dispatching to different agents
   based on the routing config.
2. **JSON config file** pointed to by `PYKOCLAW_WA_AGENT_ROUTES` env var.
3. **Single-process dispatch** — agents don't receive messages separately; the
   WhatsApp bridge dispatches to each agent's `dispatch_to_agent()` with the
   agent's own DB and data_dir.
4. **Conversation naming** `wa-{agent}-{jid}` + `parse_conversation()` maps
   deliveries back to agents. Delivery polling iterates all agent DBs.

## Related

- [wa-ambient-participation.md] — Prerequisite: ambient observation model
  (batch accumulation, LLM-driven reply decisions, session resumption)
- [scheduled-task-delivery.md] — Delivery queue for task results to channels

[wa-ambient-participation.md]: wa-ambient-participation.md
[scheduled-task-delivery.md]: scheduled-task-delivery.md
