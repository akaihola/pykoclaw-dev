# Telegram Gateway Plugin

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: Build a `pykoclaw-telegram` plugin that connects Telegram chats to pykoclaw agents. Follow the same plugin architecture as Matrix, WhatsApp, and Slack gateways: long-lived connection, conversation routing through `pykoclaw-messaging`, and MCP tooling for agent-initiated sends.
>
> **Deliverables**:
>
> - `pykoclaw-telegram` workspace package with plugin registration
> - Telegram bot connection and update polling/webhook integration
> - DM and group message handling with mention/reply triggering rules
> - Markdown/HTML-safe Telegram output formatting
> - MCP tool for sending Telegram messages
> - DB tables for Telegram chats and messages
>
> **Estimated Effort**: Medium
> **Depends On**: —

---

## Context

### Current State

Pykoclaw already has channel plugins for Matrix, WhatsApp, and Slack. Those plugins all follow the same architecture: entry point registration, channel-specific connection layer, persistent conversation naming, message dispatch via `pykoclaw-messaging`, and optional MCP tools for outbound actions.

Telegram support does not exist yet, but it is a high-value missing channel. It is a common bot platform, works well for both direct chats and groups, and would expand pykoclaw's reach beyond the currently supported messaging ecosystems.

### Why This Matters

Telegram is one of the most practical bot-first messaging platforms:

- Native bot model with mature APIs
- Easy 1:1 and group deployment
- Lower friction than WhatsApp for experimentation
- Good fit for both personal automation and community/group use
- Useful comparison point for the existing Matrix / Slack / WhatsApp gateway designs

Adding Telegram support would make pykoclaw more complete as a multi-channel agent platform and create a simpler alternative to WhatsApp for users who want bot-native messaging.

### Technical Path

Implement Telegram as a dedicated plugin package, likely `pykoclaw-telegram`, using a maintained Python Telegram library. Keep the architecture aligned with existing gateways:

- `TelegramPlugin(PykoClawPluginBase)` for plugin lifecycle and CLI hooks
- `TelegramSettings(BaseSettings)` for `PYKOCLAW_TELEGRAM_*` configuration
- `TelegramConnection` for long-lived update processing
- `handler.py` for parsing Telegram updates into normalized dispatch input
- `formatting.py` for safe outbound rendering in Telegram-supported markup

Prefer the smallest integration that matches existing pykoclaw patterns. Reuse `pykoclaw-messaging` for dispatch, conversation lookup, and agent interaction rather than inventing Telegram-specific orchestration.

### Key Design Questions

- **Library choice**: choose a maintained Python Telegram library with good async support
- **Transport mode**: start with polling for simplicity, or support webhooks if that meaningfully improves deployability
- **Trigger semantics**: define when the bot responds in groups (DM always, mention/reply in groups, optional ambient mode later)
- **Formatting**: decide between Telegram MarkdownV2 and HTML output modes based on escaping complexity and reliability
- **Identity model**: define conversation naming and sender labeling conventions consistent with other channel plugins
- **Media scope**: start text-first, or include image/document handling in the initial plugin boundary

---

## Work Objectives

### Core Objective

A working Telegram gateway that receives messages from Telegram chats, dispatches them to the agent through the existing pykoclaw messaging architecture, and delivers responses back to Telegram with correct routing and formatting.

### Must Have

- Dedicated `pykoclaw-telegram` workspace package
- Plugin entry point registration in `pykoclaw.plugins`
- Bot authentication via environment/config settings
- Receive inbound text messages from DMs and groups
- Clear trigger rules for DMs, mentions, and replies in groups
- Conversation naming scheme consistent with other channels
- Dispatch through `dispatch_to_agent()`
- Outbound send capability for agent responses
- Safe Telegram formatting for outbound text
- Tests covering update parsing, routing, and outbound formatting

### Nice to Have

- Bot commands such as `/help` or `/reset`
- Photo/image inbound support via `pykoclaw-vision`
- Multi-agent routing in groups
- Delivery acknowledgements or typing indicators if supported cleanly
- MCP tool for channel history / recent context fetches

### Must NOT Have

- No Telegram-specific parallel agent framework
- No custom scheduler logic outside existing pykoclaw scheduling systems
- No large core changes if the plugin boundary is sufficient
- No attempt to solve every Telegram media type in v1

---

## Verification Strategy

- Unit test: Telegram update payload → normalized inbound message handling
- Unit test: group mention/reply logic triggers correctly
- Unit test: outbound formatting escapes Telegram markup safely
- Integration test: inbound Telegram message → agent response round-trip
- Integration test: conversation naming and persistence match expected DB behavior
- Manual verification: DM and group chat both work with the chosen trigger rules

---

## Proposed Implementation Shape

1. Create new workspace package `pykoclaw-telegram/`
2. Add plugin settings, plugin registration, and connection lifecycle
3. Parse Telegram updates into shared message-dispatch calls
4. Implement outbound response formatting and sending
5. Add DB tables/migrations for Telegram chats and messages if needed
6. Add tests and minimal operational docs

---

## Notes

Treat Telegram as a first-class gateway/plugin, not a one-off integration. Keep it aligned with pykoclaw's minimal-core architecture and shared messaging patterns so future channel additions stay coherent.
