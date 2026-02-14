# Pykoclaw — Development Guide

## Project overview

Pykoclaw is a modular Python AI agent ecosystem. This is the `pykoclaw-dev`
workspace root that aggregates five packages via uv workspace. See `README.md`
for the full ecosystem map.

## Build & run

- **Package manager:** uv (NEVER use pip/virtualenv directly)
- **Python:** >= 3.12
- **Install deps:** `uv sync`
- **Run tests:** `uv run pytest`
- **Run CLI:** `uv run pykoclaw`
- **Editable install:** `./install-dev.sh`
- **Pull all subrepos:** `./pull-all.sh`

## Workspace structure

Each subdirectory is a separate git repo AND a uv workspace member:

| Package               | Import name          | Role                                     |
| --------------------- | -------------------- | ---------------------------------------- |
| `pykoclaw/`           | `pykoclaw`           | Core: CLI, plugins, agent, DB, scheduler |
| `pykoclaw-chat/`      | `pykoclaw_chat`      | Terminal REPL plugin                     |
| `pykoclaw-whatsapp/`  | `pykoclaw_whatsapp`  | WhatsApp channel plugin                  |
| `pykoclaw-messaging/` | `pykoclaw_messaging` | Shared dispatch library                  |
| `pykoclaw-acp/`       | `pykoclaw_acp`       | Agent Client Protocol plugin             |

## Code conventions

- Type hints on ALL function signatures.
- `snake_case` for functions/variables, `PascalCase` for classes.
- Use `pathlib.Path` over `os.path`.
- Use `textwrap.dedent()` for ALL multi-line strings.
- Keep code simple and minimal — avoid over-engineering.
- Pydantic models for data classes (`pykoclaw/models.py`).
- Pydantic Settings for configuration with `PYKOCLAW_` env prefix.
- Plugins implement `PykoClawPlugin` protocol or extend `PykoClawPluginBase`.
- Entry points group: `pykoclaw.plugins`.

## Architecture patterns

- **Plugin discovery:** `importlib.metadata.entry_points(group="pykoclaw.plugins")`
- **Agent streaming:** `query_agent()` is an async generator yielding `AgentMessage`
- **Channel dispatch:** channel plugins call `dispatch_to_agent()` from
  `pykoclaw-messaging`, which handles conversation lookup + agent query + session
  persistence.
- **Channel prefix:** conversations are named `{prefix}-{id}` (e.g. `wa-<jid>`,
  `acp-<uuid>`).
- **DB:** SQLite with `ThreadSafeConnection` wrapper. Tables: `conversations`,
  `scheduled_tasks`, `task_run_logs`. Plugins add tables via `get_db_migrations()`.
- **MCP tools:** defined in `pykoclaw/tools.py`, created via
  `create_sdk_mcp_server()` from `claude-agent-sdk`.

## Testing

- Framework: `pytest` (+ `pytest-asyncio` for async tests)
- Run all: `uv run pytest`
- Run single package: `uv run pytest pykoclaw/tests/`
- Tests live in `tests/` within each package directory.

## Key files to know

| File                                                    | Purpose                                  |
| ------------------------------------------------------- | ---------------------------------------- |
| `pykoclaw/src/pykoclaw/agent_core.py`                   | `query_agent()` — the central agent loop |
| `pykoclaw/src/pykoclaw/plugins.py`                      | Plugin protocol + discovery + migrations |
| `pykoclaw/src/pykoclaw/db.py`                           | DB init, ThreadSafeConnection, all CRUD  |
| `pykoclaw/src/pykoclaw/config.py`                       | Settings (Pydantic Settings)             |
| `pykoclaw/src/pykoclaw/tools.py`                        | MCP tool definitions                     |
| `pykoclaw-messaging/src/pykoclaw_messaging/dispatch.py` | `dispatch_to_agent()`                    |
| `pykoclaw-acp/src/pykoclaw_acp/server.py`               | ACP JSON-RPC server                      |
| `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py` | WhatsApp connection                      |

## Memory system

This project uses a structured memory system in `.memory/`. See
[`.memory/INDEX.md`][memory index] for the cross-reference index.

**Rule: continuously record important learnings.**

After completing any non-trivial task, ask yourself:

1. Did I discover something non-obvious about the codebase?
2. Did I hit a pitfall or gotcha that would trip someone up?
3. Did I learn a pattern or convention not documented elsewhere?
4. Did I make a design decision that should be remembered?

If yes to any, create or update a memory file. Keep each file short (< 30
lines) and focused on ONE topic. Always update [`.memory/INDEX.md`][memory index]
when adding or modifying memory files.

### Memory file format

```markdown
# <Topic Title>

**Tags:** tag1, tag2
**Related:** [other-file.md], [another.md]

<Content — keep it brief and actionable>

[other-file.md]: other-file.md
[another.md]: another.md
```

## Important gotchas

- Neonize timestamps are in **milliseconds** — divide by 1000.
- `client.me` is not a JID — use `client.me.JID`.
- WhatsApp plugin uses 3 threads sharing one SQLite connection — all DB access
  goes through `ThreadSafeConnection`.
- The workspace root `pyproject.toml` has no deps — it only declares workspace
  members.
- Each subdir is its own git repo. Commits go into the individual repos, not
  this workspace root (except for workspace-level files like this one).

[memory index]: .memory/INDEX.md
