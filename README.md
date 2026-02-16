# Pykoclaw

A modular Python AI agent ecosystem built on the Claude Agent SDK. Pykoclaw
provides a plugin-based CLI framework for running Claude-powered agents across
multiple communication channels, with built-in conversation persistence and task
scheduling.

This is the **development workspace** (`pykoclaw-dev`) that aggregates all
subprojects as a [uv workspace].

## Ecosystem overview

```
pykoclaw-dev (this repo)
├── pykoclaw/              Core framework — CLI, plugin system, agent, DB, scheduler
├── pykoclaw-chat/         Plugin — interactive terminal REPL
├── pykoclaw-whatsapp/     Plugin — WhatsApp channel via Neonize/whatsmeow
├── pykoclaw-messaging/    Shared library — channel-agnostic dispatch_to_agent()
├── pykoclaw-acp/          Plugin — Agent Client Protocol (JSON-RPC over stdio)
└── docs/                  Research notes and integration plans
```

### Dependency graph

```
pykoclaw-chat ──────────┐
                        ▼
pykoclaw-whatsapp ──► pykoclaw-messaging ──► pykoclaw (core)
                        ▲
pykoclaw-acp ───────────┘
```

## Packages

### `pykoclaw` — Core framework

The foundation of the ecosystem. Provides:

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

### `pykoclaw-chat` — Terminal chat plugin

Interactive readline-based REPL for conversing with a Claude agent.

- Named conversations: `pykoclaw chat <name>`
- Session resumption across restarts
- Per-conversation `CLAUDE.md` instructions
- Shared readline history

### `pykoclaw-whatsapp` — WhatsApp plugin

Connects a Claude agent to WhatsApp using [Neonize] (Python wrapper for the
whatsmeow Go library).

- QR code authentication: `pykoclaw whatsapp auth`
- Long-running listener: `pykoclaw whatsapp run`
- Trigger-based activation (`@Andy` mention or self-chat)
- Sliding window conversation context via `wa_messages` table
- `send_message` and `get_chat_history` MCP tools
- Thread-safe SQLite with `ThreadSafeConnection` (3-thread model)

### `pykoclaw-messaging` — Shared dispatch library

Channel-agnostic dispatch kernel used by WhatsApp, ACP, and future channel
plugins (e.g. Telegram).

- `dispatch_to_agent()` — conversation lookup, `query_agent()` call, streaming
  text callback, session persistence
- `DispatchResult` — aggregated response text + session ID
- Channel prefix convention: `wa-`, `acp-`, `tg-`, etc.

### `pykoclaw-acp` — Agent Client Protocol plugin

Exposes pykoclaw as an ACP-compatible agent over JSON-RPC 2.0 on stdio.

- Methods: `initialize`, `session/new`, `session/prompt`
- Streaming via `session/update` notifications
- Backed by `pykoclaw-messaging` dispatch

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

## Configuration

| Variable             | Default                   | Description                                       |
| -------------------- | ------------------------- | ------------------------------------------------- |
| `PYKOCLAW_DATA`      | `~/.local/share/pykoclaw` | Data directory (database, conversations, history)  |
| `PYKOCLAW_MODEL`     | `claude-opus-4-6`         | Claude model to use                                |
| `PYKOCLAW_CLI_PATH`  | *(bundled)*               | Path to Claude CLI binary (overrides bundled SDK)  |

WhatsApp-specific settings: see
[pykoclaw-whatsapp README].

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
[pykoclaw-whatsapp README]: pykoclaw-whatsapp/README.md
