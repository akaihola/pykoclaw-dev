# pykoclaw-dev

[![Built with Claude Code](https://img.shields.io/badge/Built_with-Claude_Code-6f42c1?logo=anthropic&logoColor=white)](https://claude.ai/code)

> This project is developed by an AI coding agent ([Claude Code](https://claude.ai/code)), with human oversight and direction.

Private development workspace for the Pykoclaw ecosystem.

This repository is **not** the public core project. It is the private
`pykoclaw-dev` umbrella repo that aggregates the public `pykoclaw` core repo
plus related plugin and support-package repos as a single [uv workspace].

The public core repository lives in [`pykoclaw/`](pykoclaw/README.md).

Every currently present workspace package is linked below so this root README is
also a directory of the full ecosystem inside the dev workspace.

## Ecosystem overview

```
pykoclaw-dev (this repo)
├── pykoclaw/              Core framework — CLI, plugin system, agent, DB, scheduler
├── pykoclaw-chat/         Plugin — interactive terminal REPL
├── pykoclaw-whatsapp/     Plugin — WhatsApp channel via Neonize/whatsmeow
├── pykoclaw-matrix/       Plugin — Matrix/Element channel via matrix-nio
├── pykoclaw-messaging/    Plugin/library — dispatch_to_agent() + pykoclaw send
├── pykoclaw-acp/          Plugin — Agent Client Protocol (JSON-RPC over stdio)
├── pykoclaw-slack/        Plugin — Slack gateway via Socket Mode
├── pykoclaw-vision/       Library — shared Gemini image-analysis tooling
└── docs/                  Research notes and integration plans
```

### Dependency graph

```
pykoclaw-chat ──────────┐
                        ▼
pykoclaw-whatsapp ──► pykoclaw-messaging ──► pykoclaw (core)
        │               ▲
        └──────────► pykoclaw-vision
                        ▲
pykoclaw-matrix ────────┤
                        │
pykoclaw-acp ───────────┤
                        │
pykoclaw-slack ─────────┴──────► pykoclaw-vision
```

## Packages

### [`pykoclaw`](pykoclaw/README.md) — Public core repository

The public core project in this workspace. It provides:

- **Plugin system** — auto-discovery via Python entry points
  (`pykoclaw.plugins` group). Plugins register CLI commands, MCP tools, DB
  migrations, and configuration classes.
- **Agent core** — `query_agent()` async generator that streams Claude responses
  through the Claude Agent SDK with MCP tool support.
- **Conversation persistence** — SQLite-backed conversations with session ID
  tracking for cross-restart resumption.
- **Task scheduling** — cron, interval, and one-shot task execution with
  `isolated` or `group` context modes.
- **MCP tools** — built-in `schedule_task`, `list_tasks`, `pause_task`,
  `resume_task`, `cancel_task` exposed to the agent.
- **CLI** — Click-based with `pykoclaw conversations`, `pykoclaw tasks`,
  `pykoclaw scheduler`.
- **Configuration** — Pydantic Settings with `PYKOCLAW_` env prefix and `.env`
  file support.

### [`pykoclaw-chat`](pykoclaw-chat/README.md) — Plugin repository

Interactive readline-based REPL for conversing with a Claude agent.

- Named conversations: `pykoclaw chat <name>`
- Session resumption across restarts
- Per-conversation `CLAUDE.md` instructions
- Shared readline history

### [`pykoclaw-whatsapp`](pykoclaw-whatsapp/README.md) — Plugin repository

Connects a Claude agent to WhatsApp using [Neonize] (Python wrapper for the
whatsmeow Go library).

- QR code authentication: `pykoclaw whatsapp auth`
- Long-running listener: `pykoclaw whatsapp run`
- Ambient participation with batch accumulation (default 90 s window)
- Multi-agent group routing — multiple agent personalities per WhatsApp account
- Hard mention routing (`@AgentName` flushes batch immediately, forces reply)
- Per-agent DB isolation (each agent gets its own conversations + session state)
- `send_message` and `get_chat_history` MCP tools
- Thread-safe SQLite with `ThreadSafeConnection` (3-thread model)

### [`pykoclaw-matrix`](pykoclaw-matrix/README.md) — Plugin repository

Connects a Claude agent to [Matrix] rooms using [matrix-nio] with full E2EE
support.

- Login + cross-signing: `pykoclaw matrix login`, `pykoclaw matrix verify`
- Long-running listener: `pykoclaw matrix run`
- Ambient listening with trigger-based replies (`@Andy` mention or DM)
- Rich formatting — Markdown → Matrix HTML (bold, code, tables, strikethrough,
  auto-linked URLs, task lists with emoji checkboxes)
- Mermaid diagram rendering — ` ```mermaid ` `` blocks → inline PNG images
- Image file uploads — absolute paths to images in agent text sent as `m.image`
- Batch accumulation with configurable window (default 90 s)
- Typing indicator while the agent processes
- `send_matrix_message` and `get_matrix_history` MCP tools

### [`pykoclaw-messaging`](pykoclaw-messaging/README.md) — Support-package repository

Channel-agnostic dispatch kernel used by WhatsApp, Matrix, ACP, Slack, and
future channel plugins (e.g. Telegram). It also registers the `pykoclaw send`
CLI command via the `pykoclaw.plugins` entry-point group.

- `dispatch_to_agent()` — conversation lookup, `query_agent()` call, streaming
  text callback, session persistence
- `pykoclaw send <conversation> <prompt>` — one-off dispatch plus optional queue delivery
- `DispatchResult` — aggregated response text + session ID
- Channel prefix convention: `wa-{agent}-`, `matrix-`, `acp-`, `slack-`, `tg-`, etc.

### [`pykoclaw-acp`](pykoclaw-acp/README.md) — Plugin repository

Exposes pykoclaw as an ACP-compatible agent over JSON-RPC 2.0 on stdio.

- Methods: `initialize`, `session/new`, `session/prompt`
- Streaming via `session/update` notifications
- Worker subprocesses are evicted after an idle timeout (default 30 minutes)
- Backed by `pykoclaw-messaging` dispatch

### [`pykoclaw-slack`](pykoclaw-slack/README.md) — Plugin repository

Connects Slack workspaces to pykoclaw agents via Socket Mode (no public URL needed).
Inspired by and validated against the OpenClaw and nanobot reference implementations.

- **Socket Mode** — uses `xapp-...` App-Level Token; no HTTP ingress required
- **Batch accumulation** — debounces rapid messages before dispatching to agent
- **Hard-mention detection** — `@BotName` or DM triggers immediate flush
- **Thread-scoped sessions** — each Slack thread gets its own isolated Claude session
  (`C12345:t:<thread_ts>` dispatch key)
- **replyToMode** — `all` (default) / `first` / `off` controls threading behaviour
- **mrkdwn formatting** — [`slackify-markdown`][slackify-markdown] library with a
  table pre-pass (Markdown tables → `• *Header*: value` bullets)
- **Emoji ACK reaction** — reacts with `:eyes:` on receipt, removes after reply
- **Channel type inference** — `D`/`C`/`G` prefix → `im`/`channel`/`group` (no API call)
- **Bot filtering** — own messages always dropped; other bots gated by `allow_bots`
- **Inbound images** — images uploaded to Slack are downloaded (via
  `url_private_download` + bot-token auth) and stored in
  `{data_dir}/slack_attachments/{channel_id}/`. The `analyze_image` MCP tool
  (from `pykoclaw-vision` / Gemini) is registered so the agent can describe,
  OCR, or reason about images. Requires the `files:read` OAuth scope on the Slack app.
- **Delivery queue** — scheduled task results delivered via `slack-` prefix

Required env vars:

```
PYKOCLAW_SLACK_BOT_TOKEN=xoxb-...
PYKOCLAW_SLACK_APP_TOKEN=xapp-...
PYKOCLAW_SLACK_TRIGGER_NAME=YourBotName
```

Optional env vars:

```
PYKOCLAW_SLACK_ACK_EMOJI=eyes        # empty string to disable
PYKOCLAW_SLACK_REPLY_TO_MODE=all     # all | first | off
PYKOCLAW_SLACK_ALLOW_BOTS=false      # true to allow other Slack bots
PYKOCLAW_SLACK_BATCH_WINDOW_SECONDS=90
```

```bash
uv run pykoclaw slack run
uv run pykoclaw slack healthcheck
```

### [`pykoclaw-vision`](pykoclaw-vision/README.md) — Support-package repository

Shared Gemini-powered image tooling used by channel plugins.

- Exposes the `analyze_image` MCP tool factory
- Used by WhatsApp and Slack for inbound image understanding
- Configured with `GEMINI_API_KEY` and optional `PYKOCLAW_VISION_MODEL`

[slackify-markdown]: https://pypi.org/project/slackify-markdown/

## Development

**Requirements:** Python >= 3.12, [uv]

```bash
# Clone with all subprojects
git clone https://github.com/akaihola/pykoclaw-dev
cd pykoclaw-dev

# Install workspace dependencies
uv sync

# Run tests across all packages
uv run pytest

# Install all plugins in editable mode (for local `pykoclaw` CLI)
./install-dev.sh

# Pull --rebase all subproject repos
./pull-all.sh
```

## Feature worktrees

For cross-repo feature development, use the worktree scripts in `bin/`.
These create parallel git worktree checkouts of all repos on a matching
`feature/<name>` branch.

```bash
# Create a feature worktree (branches + worktrees + uv sync)
bin/create-worktree.sh my-feature

# List active worktrees
bin/list-worktrees.sh

# Run tests against a worktree
bin/qa-check.sh my-feature

# Tear down when done
bin/cleanup-worktree.sh my-feature
```

See [worktree workflow docs] for full details and terminology.

## Configuration

| Variable            | Default                   | Description                                       |
| ------------------- | ------------------------- | ------------------------------------------------- |
| `PYKOCLAW_DATA`     | `~/.local/share/pykoclaw` | Data directory (database, conversations, history) |
| `PYKOCLAW_MODEL`    | `claude-opus-4-6`         | Claude model to use                               |
| `PYKOCLAW_CLI_PATH` | _(bundled)_               | Path to Claude CLI binary (overrides bundled SDK) |
| `BRAVE_API_KEY`     | _(unset)_                 | Enables the `brave_search` MCP tool               |

WhatsApp-specific settings: see [pykoclaw-whatsapp README].
Matrix-specific settings: see [pykoclaw-matrix README].
Slack and vision settings are documented inline in this workspace README and in
package source until dedicated package READMEs are added.

## Data directory layout

```
~/.local/share/pykoclaw/
  pykoclaw.db                # SQLite database
  .env                       # Environment overrides (optional)
  history                    # Readline history (shared)
  CLAUDE.md                  # Global system prompt (user-editable)
  conversations/
    <name>/                  # Per-conversation working directory
      CLAUDE.md              # Per-conversation instructions
```

## Writing a plugin

Implement the `PykoClawPlugin` protocol (or extend `PykoClawPluginBase`) and
register via entry points:

```toml
[project.entry-points."pykoclaw.plugins"]
myplugin = "my_package:MyPlugin"
```

See `pykoclaw/src/pykoclaw/plugins.py` for the full protocol interface.

[uv workspace]: https://docs.astral.sh/uv/concepts/workspaces/
[uv]: https://docs.astral.sh/uv/
[Neonize]: https://github.com/krypton-byte/neonize
[Matrix]: https://matrix.org
[matrix-nio]: https://github.com/poljar/matrix-nio
[pykoclaw-whatsapp README]: pykoclaw-whatsapp/README.md
[pykoclaw-matrix README]: pykoclaw-matrix/README.md
[worktree workflow docs]: docs/worktree-workflow.md
