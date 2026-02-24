# Slack Gateway Plugin

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: Build a `pykoclaw-slack` plugin that connects Slack workspaces
> to pykoclaw agents. Follows the same plugin architecture as WhatsApp and Matrix
> gateways — Slack Bot Token + Socket Mode for real-time messaging, batch
> accumulation, and dispatch to agent via `pykoclaw-messaging`.
>
> **Deliverables**:
>
> - `pykoclaw-slack` workspace package with plugin protocol implementation
> - Socket Mode connection for real-time message reception
> - Batch accumulation with hard-mention detection
> - Slack Block Kit / mrkdwn output formatting
> - MCP tools: `send_slack_message`, `get_channel_history`
> - DB migrations for `slack_messages`, `slack_channels`
>
> **Estimated Effort**: Medium
> **Depends On**: —

---

## Context

### Current State

Pykoclaw has WhatsApp (Neonize) and Matrix (matrix-nio) gateways. Both follow
the same plugin pattern: entry point registration, `PykoClawPlugin` protocol,
CLI commands, DB migrations, MCP tools, and dispatch via `pykoclaw-messaging`.

No Slack support exists yet. The Coleaders team needs a Slack-connected agent
as their primary interaction channel.

### Why This Matters

Slack is the dominant team communication tool. Adding a Slack gateway makes
pykoclaw viable for team/workplace agent deployments — starting with Coleaders
but reusable for any Slack workspace.

### Technical Path

Use the official `slack-sdk` Python package with **Socket Mode** (WebSocket-based,
no public URL needed). This mirrors the Neonize approach: long-lived connection,
event callbacks, no HTTP server required.

Key components (mirroring WhatsApp/Matrix pattern):
- `SlackPlugin(PykoClawPluginBase)` — plugin entry point
- `SlackSettings(BaseSettings)` — config via `PYKOCLAW_SLACK_*` env vars
- `SlackConnection` — Socket Mode lifecycle manager
- `MessageHandler` + `BatchAccumulator` — message parsing and debounce
- `formatting.py` — Markdown → Slack mrkdwn conversion

### Slack API Requirements

- **Bot Token** (`xoxb-...`): For sending messages and reading channel info
- **App-Level Token** (`xapp-...`): For Socket Mode WebSocket connection
- **Scopes needed**: `chat:write`, `channels:history`, `channels:read`,
  `groups:history`, `groups:read`, `im:history`, `im:read`, `app_mentions:read`
- **Socket Mode**: Enabled in Slack App settings (no Events API URL needed)

---

## Work Objectives

### Core Objective

A working Slack gateway that receives messages, dispatches to Claude, and sends
responses — following the same patterns as WhatsApp and Matrix gateways.

### Must Have

- Socket Mode connection (no public URL required)
- Message event handling (`message`, `app_mention`)
- Batch accumulation with configurable window (default 90s)
- Hard mention detection (`@BotName` or app_mention events)
- Dispatch to agent via `dispatch_to_agent()`
- Reply extraction from `<reply>` tags
- Markdown → Slack mrkdwn formatting
- Thread-aware replies (reply in thread if original was in thread)
- MCP tool for sending messages
- DB tables for message history

### Nice to Have

- Multi-agent routing (like WhatsApp `agent-routes.json`)
- Slack Block Kit rich formatting
- File/image attachment support (Slack → agent vision)
- Slash commands (`/ask-agent`)
- Emoji reactions as acknowledgment

### Must NOT Have

- No OAuth installation flow (single-workspace, token-based)
- No HTTP server (Socket Mode only)
- No Slack-specific session management (use pykoclaw-messaging dispatch)

---

## Verification Strategy

- Unit test: mock Socket Mode events → verify handler parses correctly
- Unit test: batch accumulator timing and hard mention flushing
- Unit test: Markdown → mrkdwn formatting conversion
- Integration: send message in Slack → verify agent responds in thread
- Healthcheck: `pykoclaw slack healthcheck` (connect, verify token, disconnect)
