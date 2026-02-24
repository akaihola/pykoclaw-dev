# Pykoclaw — Development Guide

## Project overview

Pykoclaw is a modular Python AI agent ecosystem. This is the `pykoclaw-dev`
workspace root that aggregates six packages via uv workspace. See `README.md`
for the full ecosystem map.

## ⚠️ Mitto / ACP Issues — Read First!

**Before starting ANY work on Mitto or pykoclaw-acp problems**, read
[`ACP_ISSUES_LOG.md`][acp-log] — the comprehensive log of all connection
issues, root causes, failed approaches, and fixes. This is a recurring
problem area with subtle bugs at the anyio/asyncio boundary. The log
prevents re-treading failed approaches.

## Practices

- Always write useful insights, practices and rules applicable to all pykoclaw
  repos/components/plugins immediately into `./CLAUDE.md` (this file).
  Details specific to a single repo can go to that repo's `./pykoclaw*/.claude/CLAUDE.md`.
- **Always use feature worktrees** for non-trivial work. Only skip for the
  simplest obvious quick fixes. Use `bin/create-worktree.sh <feature-name>` to
  set up, work in the worktree, and commit there — not on main.
- **Always check docs once code and tests are complete** — before considering
  any task done, check every README and memory file touched by or relevant to
  the change. Update them without waiting to be asked. Specifically:
  - Any new user-visible behaviour → add a section to the relevant `README.md`.
  - Any non-obvious pattern, gotcha, or design decision → add or update a
    `.memory/*.md` file and update `.memory/INDEX.md`.
  - Never commit a docs update separately from the feature commit on `main`;
    commit it as part of the same logical unit (or a follow-up commit in the
    same worktree before merging).

## Build & run

- **Package manager:** uv (NEVER use pip/virtualenv directly)
- **Python:** >= 3.12
- **Install deps:** `uv sync`
- **Run tests:** `uv run pytest`
- **Run CLI:** `uv run pykoclaw`
- **Deploy:** `./install-dev.sh` (never inspect it first — just run it)
- **Deploy + verify:** combine in one call:
  `./install-dev.sh && sleep 3 && export XDG_RUNTIME_DIR="/run/user/$(id -u)" && systemctl --user status mitto-web | head -20`
- **`install-dev.sh` restarts all active services** (mitto-web,
  pykoclaw-whatsapp, pykoclaw-matrix) so they pick up code changes.
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
| `pykoclaw-matrix/`    | `pykoclaw_matrix`    | Matrix/Element channel plugin            |

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
- In Markdown files, use [reference links] — never inline `[text](url)`.
  Collect all link definitions at the end of the file.

## Architecture patterns

- **Plugin discovery:** `importlib.metadata.entry_points(group="pykoclaw.plugins")`
- **Agent streaming:** `query_agent()` is an async generator yielding `AgentMessage`
- **Channel dispatch:** channel plugins call `dispatch_to_agent()` from
  `pykoclaw-messaging`, which handles conversation lookup + agent query + session
  persistence.
- **Two SDK message loops:** WhatsApp and the scheduler use
  `query_agent()` → `ClaudeSDKClient`. Mitto/ACP uses its own independent
  loop in `ClientPool._query()`. Bugs in SDK message handling must be fixed
  in **both** places.
- **Channel prefix:** conversations are named `{prefix}-{id}` (e.g.
  `wa-ressu-<jid>`, `matrix-<room_id>`, `acp-<uuid>`). WhatsApp includes the
  agent name: `wa-{agent}-{jid}`.
- **DB:** SQLite with `ThreadSafeConnection` wrapper. Tables: `conversations`,
  `scheduled_tasks`, `task_run_logs`, `delivery_queue`. Plugins add tables via
  `get_db_migrations()`.
- **MCP tools:** defined in `pykoclaw/tools.py`, created via
  `create_sdk_mcp_server()` from `claude-agent-sdk`.

## Testing

- Framework: `pytest` (+ `pytest-asyncio` for async tests)
- Run all: `uv run pytest`
- Run single package: `uv run pytest pykoclaw/tests/`
- **For packages with extra deps** (e.g. `pykoclaw-matrix`): `cd` into the
  subpackage and run `uv run --with pytest pytest tests/` — running from
  the workspace root won't find the package.
- Tests live in `tests/` within each package directory.
- **Always set `PYKOCLAW_DATA` to a temporary directory** before running tests
  or dev instances. Never let dev/test code touch the production database at
  `~/.local/share/pykoclaw/pykoclaw.db`. Example:
  `export PYKOCLAW_DATA=/tmp/pykoclaw-dev-<feature>`. The staging script
  (`bin/staging.sh`) already does this — but manual runs need it too.
- **Bug reports:** when a malfunction is reported, always reproduce the issue
  first by writing a failing test case before implementing the fix (red → green
  workflow).
- **Schema changes:** when adding columns to a `CREATE TABLE IF NOT EXISTS`
  statement, always also add `ALTER TABLE ADD COLUMN` migration logic in
  `init_db()` and a test that creates an old-schema database, calls `init_db()`,
  and verifies the new columns exist. SQLite's `IF NOT EXISTS` silently skips
  the whole statement if the table already exists — it never adds missing
  columns.

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
| `pykoclaw-whatsapp/src/pykoclaw_whatsapp/routing.py`    | Multi-agent group routing config         |
| `pykoclaw-matrix/src/pykoclaw_matrix/connection.py`     | Matrix connection                        |

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

## Self-improvement rules

- When the user asks to adopt and remember a new behavior or rule, add it to
  this file (`./CLAUDE.md`).
- When a task requires reading a lot of code or docs before you can start, edit
  the easily accessible documentation within the relevant repository (e.g.
  `CLAUDE.md`, `README.md`) to give better pointers and base information for
  next time.
- When you notice documentation vs. code discrepancies, raise a flag to the user
  and offer to either correct the documentation or fix the code to match the
  spec.

## Feature worktree workflow

For cross-repo feature work, use the **feature worktree** scripts in `bin/`.
Full docs: [worktree workflow docs].

| Command                                                | What it does                                                                                        |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `bin/create-worktree.sh <feature>`                     | Create worktrees + branches + AoE                                                                   |
| `bin/qa-check.sh [feature]`                            | Run full test suite against worktree                                                                |
| `bin/staging.sh <feature>`                             | Launch Mitto web + ACP for user review                                                              |
| `bin/merge-feature.sh <feature>`                       | Merge feature branches → main                                                                       |
| `./install-dev.sh`                                     | Deploy (editable reinstall)                                                                         |
| `bin/cleanup-worktree.sh <feature>`                    | Tear down worktrees + AoE + temp dirs                                                               |
| `bin/list-worktrees.sh`                                | List active feature worktrees                                                                       |
| `bin/diff-feature.sh <feature>`                        | Browse all cross-repo diffs (fzf+delta)                                                             |
| `bin/diff-repos.sh [--root=DIR] [--before=TIME] [REF]` | General multi-repo diff browser: uncommitted changes, any ref, or vs last commit before a timestamp |

Key concepts:

- A **feature** is a short name like `my-feature`
- Creates `feature/<name>` branch in every repo (root + subrepos)
- Worktree root: `~/pykoclaw-dev/<feature>/` — this IS the pykoclaw-dev worktree
- Subrepos sit directly inside: `~/pykoclaw-dev/<feature>/pykoclaw/` etc.
- **Always `cd ~/pykoclaw-dev/<feature>/` and run `uv run` from there** — never
  run tests from the main workspace against worktree files. The main workspace
  `.venv` imports its own installed packages, not the worktree source.
- AoE sessions are optional (scripts degrade gracefully)
- **Cleanup does NOT delete feature branches** — do that manually

### Common worktree operations

**Always use the scripts** — never run manual `git` commands for worktree
operations. The scripts handle multi-worktree complexity (e.g., "main is
already checked out" errors).

**Checking commits ahead:**

```bash
# Compare feature branch against main in ~/pykoclaw
cd ~/pykoclaw-dev/<feature>/<repo>
git log ~/pykoclaw/<repo>/HEAD..HEAD --oneline
```

**Rebasing:** The scripts handle rebasing automatically. If you must rebase
manually, use `git rebase origin/main` from within the worktree.

**Merging into main:** Use `bin/merge-feature.sh <feature>`. This merges the
feature branch into local main only — it does NOT push to origin. Push
separately if needed.

## Backlog management

Plan files in `.sisyphus/plans/` carry `## Status:` and `## Priority:` metadata.
`.sisyphus/BACKLOG.md` is the **auto-generated** dashboard — never edit it by hand.

**After any change to plan files**, run the validation + regeneration script:

```bash
# Validate plan files and regenerate BACKLOG.md (MANDATORY after any plan change)
bin/update-backlog.sh

# Validate only (no regeneration)
bin/update-backlog.sh --check
```

A **pre-commit hook** also runs validation and auto-regenerates `BACKLOG.md`
when plan files are committed. This is a safety net — don't rely on it;
always run `bin/update-backlog.sh` explicitly after editing plans.

### Plan file requirements

- Every plan **must** have `## Status:` (Done, Backlog, In Progress, Blocked)
- Non-Done plans **should** have `## Priority:` (1, 2, 3...)
- Done plans **must** have `## Completed: YYYY-MM-DD`

### Querying the backlog

```bash
.sisyphus/query_backlog.py                        # table view
.sisyphus/query_backlog.py --status Backlog        # filter by status
.sisyphus/query_backlog.py --format mermaid        # dependency graph
.sisyphus/query_backlog.py --all                   # all statuses
.sisyphus/query_backlog.py --sort completed        # by completion date
```

## NixOS boundary rule

**Never put Nix/NixOS-specific code in any pykoclaw Python package.** All
packages (`pykoclaw`, `pykoclaw-matrix`, `pykoclaw-whatsapp`, etc.) must be
platform-agnostic. NixOS-specific configuration (browser paths, library paths,
nix-build invocations) belongs ONLY in:

- Systemd service files (`~/.config/systemd/user/*.service`)
- Deployment scripts (`install-dev.sh`, `bin/`)
- The root `pykoclaw-dev` workspace (not a published package)

If a Python package needs a resource that's platform-specific (e.g. Playwright
browsers), it should read a standard env var (`$PLAYWRIGHT_BROWSERS_PATH`) — the
deployment layer is responsible for setting it.

## Important gotchas

- **`ClaudeAgentOptions.setting_sources` controls skill discovery** — `"user"`
  loads `~/.claude/skills/`, `"project"` loads `./.claude/skills/`. Skills are
  concatenated in order and resolved by first-match, so order = precedence.
  Always use `["project", "user"]` so project skills win on name collision.
  Bundled skills (e.g. `keybindings-help`) are compiled into the binary and
  cannot be disabled individually. See [claude-sdk-setting-sources.md] memory.
- Neonize timestamps are in **milliseconds** — divide by 1000.
- `client.me` is not a JID — use `client.me.JID`.
- WhatsApp plugin uses 3 threads sharing one SQLite connection — all DB access
  goes through `ThreadSafeConnection`.
- **WhatsApp multi-agent routing** — each agent with a `data_dir` gets its own
  DB; the bridge DB (`wa_messages`, `wa_chats`) is shared. Delivery polling
  iterates all agent DBs. Conversation names include the agent:
  `wa-{agent}-{jid}`.
- The workspace root `pyproject.toml` has no deps — it only declares workspace
  members.
- Each subdir is its own git repo. Commits go into the individual repos, not
  this workspace root (except for workspace-level files like this one).
- SQLite `CREATE TABLE IF NOT EXISTS` never modifies an existing table — it
  silently does nothing. New columns need explicit `ALTER TABLE ADD COLUMN`
  migrations.
- **matrix-nio `room.is_group`** means "unnamed room", NOT "group chat". DMs
  are unnamed → `is_group=True` for DMs. Use `member_count <= 2` instead.
- **matrix-nio `server_timestamp`** is in milliseconds — divide by 1000
  before `datetime.fromtimestamp()`.
- **matrix-nio has NO cross-signing support.** Use the raw Matrix CS API
  (`/keys/device_signing/upload` + `/keys/signatures/upload`) via
  `pykoclaw matrix verify`.
- **Plugin config `.env` files** — when `PYKOCLAW_DATA` is set to a custom
  directory, plugins won't find the `.env` there unless they resolve the path
  from `os.environ["PYKOCLAW_DATA"]`. See [plugin-config-env-file.md] memory.
- **Neonize configures logging on import** — `neonize.utils.log` calls
  `logging.basicConfig(level=INFO)` the moment it is imported. This is the
  actual source of logging configuration for all WhatsApp plugin services.
  To enable DEBUG for our code without drowning in whatsmeow noise, set
  specific loggers AFTER neonize is imported:
  ```python
  for ns in ("pykoclaw", "pykoclaw_whatsapp", "pykoclaw_messaging", "claude_agent_sdk"):
      logging.getLogger(ns).setLevel(logging.DEBUG)
  ```
  The WhatsApp `run` command honours `PYKOCLAW_LOG_LEVEL=DEBUG` to trigger this.
- **`install-dev.sh` regenerates service files** — editing
  `~/.config/systemd/user/pykoclaw-whatsapp.service` directly is futile; the
  script overwrites it. To add a temporary env var (e.g. `PYKOCLAW_LOG_LEVEL`),
  set it in the environment before running the service, or modify the source
  template that `install-dev.sh` uses. Run `systemctl --user daemon-reload`
  after any manual service file edit that survives a reinstall.
- **CLI `run` commands must call `logging.basicConfig()`** — without it, all
  `log.info()` / `log.warning()` calls are silently swallowed. Always configure
  logging at the top of long-running CLI entry points.
- **Session resume has TWO failure modes** — `dispatch_to_agent()` retries
  on `ProcessError` (exit code 1), but NOT on exit code 0 + empty
  `full_text`. The latter looks like "chose silence" but completes in < 2s
  (real responses take ≥ 5s). Channel plugins must detect `hard_mention=True`
  - `full_text=""` and retry with `fresh=True`. See [session-resume-retry.md].
- **Claude SDK stderr is silently discarded** — `ClaudeAgentOptions.stderr`
  defaults to `None`, dropping all crash output. Always pass `stderr=_on_stderr`
  callback in `agent_core.py` to pipe it to `logging.getLogger("claude_agent_sdk.stderr")`.
  Claude also writes a full debug log to `~/.claude/debug/<session_id>.txt`
  regardless — check this first when diagnosing silent failures. See
  [claude-sdk-stderr-silence.md] memory note.
- **`system_prompt` is ignored on session resume** — `ClaudeAgentOptions`
  bakes the system prompt into the session at creation. On resume, the
  parameter is silently discarded. Any per-turn dynamic instructions (e.g.
  "you MUST reply to this hard mention") **must go in the user prompt**, not
  the system prompt. See [session-resume-system-prompt.md] memory note.
- **Always send typing indicators** — users assume the bot is broken if there's
  no feedback while the agent processes a message. Send platform-specific
  "typing" signals before dispatch and clear them after (e.g.
  `client.room_typing()` for Matrix).
- **Mitto ACP wrapper scripts MUST `export PYKOCLAW_DATA` explicitly** — Mitto
  launches all workspace ACP processes as children of the same `mitto-web`
  service. If one workspace's process sets `PYKOCLAW_DATA` in its environment,
  subsequent spawns inherit it, overriding the `.env` file in the new workspace's
  directory (env vars take precedence over `.env` in Pydantic Settings). Symptom:
  Ressu workspace (`~/pipsa`) reports itself as Tyko. Fix: always `export
PYKOCLAW_DATA=/home/agent/<datadir>` at the top of every wrapper script
  (`~/.local/bin/pykoclaw-ressu`, `~/.local/bin/pykoclaw-tyko`, etc.) — never
  rely solely on the `.env` file for identity-critical variables.

## Known issues

- **Older worktrees use `root/` subdirectory layout** — worktrees created before
  the `fix-worktree-script` merge have the wrapper repo checked out into a `root/`
  subdirectory with symlinked `pyproject.toml`/`uv.lock` at the feature base.
  New worktrees created from main no longer have this issue.
- **Mitto must reference the `~/.venv` or project `.venv` binary** — After
  `install-dev.sh`, the pykoclaw binary is at `~/.venv/bin/pykoclaw` (or
  `~/pykoclaw/.venv/bin/pykoclaw`). The old `uv tool` path
  (`~/.local/bin/pykoclaw`) no longer exists. Mitto's `settings.json` and
  `workspaces.json` must both point to the `.venv` binary. Mitto only reads
  config at startup — restart the service AND create a new session to pick up
  path changes.

[acp-log]: ACP_ISSUES_LOG.md
[memory index]: .memory/INDEX.md
[plugin-config-env-file.md]: .memory/plugin-config-env-file.md
[reference links]: https://spec.commonmark.org/0.31.2/#reference-link
[plugin-config-env-file.md]: .memory/plugin-config-env-file.md
[session-resume-retry.md]: .memory/session-resume-retry.md
[session-resume-system-prompt.md]: .memory/session-resume-system-prompt.md
[claude-sdk-setting-sources.md]: .memory/claude-sdk-setting-sources.md
[worktree workflow docs]: docs/worktree-workflow.md
