# WhatsApp Multi-Agent Group Routing

## Status: Done

## Priority: 2

## Completed: 2026-02-22

## TL;DR

> **Quick Summary**: Multiple pykoclaw agent personalities (Ressu, Tyko, Väinö)
> participate in WhatsApp groups through a single shared WhatsApp account. Each
> group maps to one or more agents via a JSON routing config. In multi-agent
> groups, agents prefix messages with `[AgentName]:` and follow loop prevention
> rules.
>
> **Estimated Effort**: Medium-Large
> **Depends On**: [wa-ambient-participation.md]

---

## What was built

### Core routing (`routing.py`)

- `RoutingConfig` / `AgentConfig` dataclasses with `data_dir` and `model`
  per agent
- `load_routing_config()` loads from JSON or creates single-agent default
- Group → agent lookup, multi-agent detection, conversation name
  generation/parsing

### Per-agent dispatch (`connection.py`)

- `_handle_agent_trigger()` looks up agents for a chat JID, dispatches
  sequentially
- Each agent gets its own DB connection and `data_dir` (lazy init)
- `[AgentName]:` prefixing on outgoing messages in multi-agent groups
- Multi-agent-aware system prompts with loop prevention instructions
- Per-agent hard mention routing (only the mentioned agent gets "MUST reply")
- Delivery queue parsing supports the new `wa-{agent}-{jid}` conversation
  format

### Configuration

- `PYKOCLAW_WA_AGENT_ROUTES` env var points to JSON routing config
- Fully backward compatible: without the env var, single-agent behavior is
  unchanged

### Tests

102 tests passing — 21 new tests covering routing config, multi-agent
dispatch, message prefixing, system prompt awareness, model overrides, and
hard mention routing.

### Documentation

Comprehensive README rewrite covering ambient participation, multi-agent
setup walkthrough (data dirs → JSON config → JID discovery → deployment),
per-agent isolation, and architecture diagrams.

## Design decisions

| Decision            | Choice                                    |
| ------------------- | ----------------------------------------- |
| Process model       | Single process (one neonize bridge)       |
| Config format       | JSON file referenced by env var           |
| Dispatch order      | Sequential per group                      |
| Conversation naming | `wa-{agent_lower}-{jid}`                  |
| Per-agent DB        | Each agent's `data_dir/pykoclaw.db`       |
| Message prefixing   | Applied at send layer, not by LLM         |
| Loop prevention     | System prompt instructions + `is_from_me` |

## Related

- [wa-ambient-participation.md] — Prerequisite: batch accumulation model
- [scheduled-task-delivery.md] — Delivery queue for task results

[wa-ambient-participation.md]: wa-ambient-participation.md
[scheduled-task-delivery.md]: scheduled-task-delivery.md
