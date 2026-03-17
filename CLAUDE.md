# Pykoclaw — Development Guide

## Project overview

Pykoclaw is a modular Python AI agent ecosystem. This is the `pykoclaw-dev`
workspace root that aggregates eight workspace packages via uv workspace. See
`README.md` for the full ecosystem map.

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
- **Always record Pi session metadata in artifacts** — run `session_meta` for
  the current session and use its values consistently:
  - Every commit message must contain the current Pi session `shortId`.
  - Every project, plan, task, and issue description must contain the current
    session's `Pi-Session-File` path.
- **Commit frequently during active implementation** — prefer small, logical
  commits as milestones instead of batching many unrelated edits into one large
  commit.

## Build & run

- **Package manager:** uv (NEVER use pip/virtualenv directly)
- **Python:** >= 3.12
- **Install deps:** `uv sync`
- **Run tests:** `uv run pytest`
- **Run CLI:** `uv run pykoclaw`
- **Deploy to production:** `./install-dev.sh` — installs into `~/.venv`,
  restarts all active services.
- **Deploy to testi:** `./install-testi.sh [<worktree>]` — installs into
  `~/.testi-venv`, restarts only testi services. Pass a worktree name to
  deploy a feature branch: `./install-testi.sh streaming-responses`.
- **Deploy + verify (production):** combine in one call:
  `./install-dev.sh && sleep 3 && export XDG_RUNTIME_DIR="/run/user/$(id -u)" && systemctl --user status mitto-web | head -20`
- **`install-dev.sh` restarts all active services** (mitto-web,
  pykoclaw-whatsapp, pykoclaw-matrix) so they pick up code changes.
- **Pull all subrepos:** `./pull-all.sh`

## Workspace structure

Each subdirectory is a separate git repo AND a uv workspace member:

| Package               | Import name          | Role                                                       |
| --------------------- | -------------------- | ---------------------------------------------------------- |
| `pykoclaw/`           | `pykoclaw`           | Core: CLI, plugins, agent, DB, scheduler                   |
| `pykoclaw-chat/`      | `pykoclaw_chat`      | Terminal REPL plugin                                       |
| `pykoclaw-slack/`     | `pykoclaw_slack`     | Slack gateway plugin (Socket Mode, thread-scoped sessions) |
| `pykoclaw-whatsapp/`  | `pykoclaw_whatsapp`  | WhatsApp channel plugin                                    |
| `pykoclaw-messaging/` | `pykoclaw_messaging` | Shared dispatch library                                    |
| `pykoclaw-acp/`       | `pykoclaw_acp`       | Agent Client Protocol plugin                               |
| `pykoclaw-matrix/`    | `pykoclaw_matrix`    | Matrix/Element channel plugin                              |
| `pykoclaw-vision/`    | `pykoclaw_vision`    | Vision plugin (image analysis, generation, editing)        |

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
- **Scheduled task delivery modes:** `ScheduledTask.output_mode` controls how
  the scheduler delivers results. See
  `pykoclaw/.memory/scheduled-task-output-modes.md` for the full design.
  - `deliver_final` (default) — scheduler delivers the task's final reply.
    The task must not send channel messages itself.
  - `ack_only` — the task sends the main summary to a target channel directly;
    the task's final reply is only a short acknowledgement for the default
    destination.
  Use `schedule_channel_report_task` (MCP tool) instead of `schedule_task`
  when creating channel-reporting tasks — it automatically appends the correct
  output contract so the agent does not leak progress narration or send
  duplicate messages.

## Scheduled task prompt rules

Scheduled tasks that deliver results to a channel **must** include an output
contract.  `schedule_channel_report_task` appends this automatically.  When
writing raw `schedule_task` prompts, always end with one of:

```
Output contract — mandatory:
- Work silently. No narration. No "Now I will...", "Let me...", "Done."
- Your final reply must be ONLY the ready-to-send summary/report.
- The scheduler will deliver your final reply to the configured destination.
- Do NOT send any separate message yourself.
```

or (for `ack_only`):

```
Output contract — mandatory:
- Work silently. No narration. No "Now I will...", "Let me...", "Done."
- The target-channel message must contain only the report content.
- Your final reply must be ONLY a brief acknowledgement for the default destination.
- Do NOT repeat the full summary in the acknowledgement.
```

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
| `pykoclaw/src/pykoclaw/db.py`                           | DB init, ThreadSafeConnection, all CRUD; `output_mode` column |
| `pykoclaw/src/pykoclaw/config.py`                       | Settings (Pydantic Settings)             |
| `pykoclaw/src/pykoclaw/tools.py`                        | MCP tool definitions; `schedule_channel_report_task` helper; output contract constants |
| `pykoclaw-messaging/src/pykoclaw_messaging/dispatch.py` | `dispatch_to_agent()`                    |
| `pykoclaw-acp/src/pykoclaw_acp/server.py`               | ACP JSON-RPC server                      |
| `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py` | WhatsApp connection                      |
| `pykoclaw-whatsapp/src/pykoclaw_whatsapp/routing.py`    | Multi-agent group routing config         |
| `pykoclaw-matrix/src/pykoclaw_matrix/connection.py`     | Matrix connection                        |

## Memory system

This project uses a structured memory system in `pykoclaw/.memory/`. See
[`pykoclaw/.memory/INDEX.md`][memory index] for the cross-reference index.

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
| `bin/new-plugin.sh <feature> <plugin-name>`            | Create a new plugin subrepo inside an existing feature worktree                                     |
| `bin/qa-check.sh [feature]`                            | Run full test suite against worktree                                                                |
| `bin/staging.sh <feature>`                             | Launch Mitto web + ACP for user review                                                              |
| `bin/merge-feature.sh <feature>`                       | Adopt new plugins + merge feature branches → main                                                   |
| `./install-dev.sh`                                     | Deploy (editable reinstall)                                                                         |
| `bin/cleanup-worktree.sh <feature>`                    | Tear down worktrees + AoE + temp dirs (aborts if unadopted new plugins found)                       |
| `bin/list-worktrees.sh`                                | List active feature worktrees                                                                       |
| `bin/diff-feature.sh <feature>`                        | Browse all cross-repo diffs (fzf+delta)                                                             |
| `bin/diff-repos.sh [--root=DIR] [--before=TIME] [REF]` | General multi-repo diff browser: uncommitted changes, any ref, or vs last commit before a timestamp |

Key concepts:

- A **feature** is a short name like `my-feature`
- Creates `feature/<name>` branch in every repo (root + subrepos)
- Worktree root: `~/prg/pykoclaw-worktrees/<feature>/` — this IS the pykoclaw-dev worktree
- Subrepos sit directly inside: `~/prg/pykoclaw-worktrees/<feature>/pykoclaw/` etc.
- **Always `cd ~/prg/pykoclaw-worktrees/<feature>/` and run `uv run` from there** — never
  run tests from the main workspace against worktree files. The main workspace
  `.venv` imports its own installed packages, not the worktree source.
- **Subrepo list is auto-detected** — scripts scan `~/prg/pykoclaw-dev/*/` for dirs with
  both `.git` and `pyproject.toml`. Never hardcode a plugin list anywhere.
- AoE sessions are optional (scripts degrade gracefully)
- **Cleanup does NOT delete feature branches** — do that manually

### Creating a new plugin during feature development

**Always use `bin/new-plugin.sh`** — never `git init` directly inside the
feature worktree. The canonical repo must be created in `~/prg/pykoclaw-dev/` first;
the worktree is then added from it.

```bash
bin/new-plugin.sh my-feature pykoclaw-myplugin
# Creates ~/prg/pykoclaw-dev/pykoclaw-myplugin/      (canonical, branch: main)
# Creates ~/prg/pykoclaw-worktrees/my-feature/pykoclaw-myplugin/  (worktree, branch: feature/my-feature)
# Updates workspace pyproject.toml on the feature branch
# Runs uv sync --all-packages

cd ~/prg/pykoclaw-worktrees/my-feature/pykoclaw-myplugin/
# ... develop, commit ...

bin/merge-feature.sh my-feature   # merges all repos including the new plugin
./install-dev.sh
bin/cleanup-worktree.sh my-feature
```

### Recovery: plugin was git-init'd directly in the worktree

If a plugin was accidentally created with `git init` at
`~/prg/pykoclaw-worktrees/<feature>/<name>/` (`.git` is a directory, not a file),
`merge-feature.sh` auto-detects and adopts it before merging — no manual steps:

```bash
bin/merge-feature.sh <feature>
# Adoption output:  Adopting '<name>': .../worktree/<name> → ~/prg/pykoclaw-dev/<name>
# Then normal merge proceeds
```

### Common worktree git operations

**Always use the scripts** — they handle all multi-worktree complexity.

**Checking commits ahead:**

```bash
cd ~/prg/pykoclaw-worktrees/<feature>/<repo>
git log ~/prg/pykoclaw-dev/<repo>/HEAD..HEAD --oneline
```

**Never use `git checkout -b`** to create feature branches. That occupies the
branch in the current checkout and makes `git worktree add` fail with "already
used by worktree". The correct sequence is `git branch <name>` (no checkout)
followed by `git worktree add <path> <name>`. The scripts do this correctly.

**Merging into main:** Use `bin/merge-feature.sh <feature>`. Merges into local
main only — does NOT push to origin. Push separately if needed.

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

## NixOS home-manager rebuild

**Never try `home-manager switch` or edit symlinked service files directly.**
Service files under `~/.config/systemd/user/` are symlinks into `/nix/store` —
editing them is silently overwritten on the next activation.

The one and only rebuild command is:

```bash
sudo -u akaihola /home/akaihola/repos/nixos-config/pull-rebase-rebuild.sh
```

This pulls akaihola's nixos-config from origin, rebases the `agent` remote
(i.e. `~/repos/nixos-config`) on top, and runs `nixos-rebuild switch`.

**Workflow:** commit changes to `~/repos/nixos-config`, then run the script.
The script pulls and rebases automatically before rebuilding.

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

- **`WebSearch` (Claude Code built-in) is US-only** — it returns empty results
  outside the US. All pykoclaw agents have the `brave_search` MCP tool
  registered automatically (reads `BRAVE_API_KEY` from env, already present
  in the systemd user environment). Prefer `brave_search` over `WebSearch`.
  For YouTube-specific searches, `yt-dlp` works without an API key:
  `yt-dlp --flat-playlist "ytsearch10:<query>" --print title --print url`
- **Testi uses `~/.testi-venv` and `~/.testi-mitto`, not `~/.venv`** — testi
  services are fully isolated from production. `install-testi.sh` deploys to
  `~/.testi-venv`; `mitto-web-testi` reads `MITTO_DIR=~/.testi-mitto` which
  has its own `settings.json` pointing the `"testi"` ACP server at
  `~/.testi-venv/bin/pykoclaw acp`. Do NOT run `install-dev.sh` to deploy to
  testi — that would deploy to production `~/.venv`.
- **`MITTO_DIR` env var controls Mitto's data directory** — by default Mitto
  uses `~/.local/share/mitto/`. Set `MITTO_DIR` to give an instance its own
  isolated `settings.json`, `workspaces.json`, and sessions.
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
- **`_extract_reply` has TWO silent-drop failure modes** — (1) Agent opens
  `<reply>` before tool calls but never closes it (unclosed-tag fallback in
  `_extract_reply` handles this). (2) Agent produces valid text with NO
  `<reply>` tag at all — typically "I cannot find X"-style responses on
  hard mentions. Handled by `_extract_hard_mention_fallback()` called after
  `_extract_reply` returns `None` when `hard_mention=True`. Logs a `WARNING`.
  Group-channel ambient silence is NOT affected. See [slack-reply-extraction.md].
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

- **`KNOWN_CHANNEL_PREFIXES` is hardcoded** — `db.py` has a frozenset that
  `resolve_delivery_target()` uses for prefix detection. Any new channel plugin
  must add its prefix here or cross-agent delivery will mangle conversation
  names. Backlog plan `dynamic-channel-prefix-discovery` replaces this with
  plugin-declared `channel_prefixes` class attributes collected at startup.
  - **pykoclaw-slack entry is `"slack"`** — added in feature/slack-gateway, verify
    it's present on any branch that adds channel plugins.
- **Older worktrees use `root/` subdirectory layout** — worktrees created before
  the `fix-worktree-script` merge have the wrapper repo checked out into a `root/`
  subdirectory with symlinked `pyproject.toml`/`uv.lock` at the feature base.
  New worktrees created from main no longer have this issue.
- **Mitto must reference the `~/.venv` or project `.venv` binary** — After
  `install-dev.sh`, the pykoclaw binary is at `~/.venv/bin/pykoclaw` (or
  `~/prg/pykoclaw-dev/.venv/bin/pykoclaw`). The old `uv tool` path
  (`~/.local/bin/pykoclaw`) no longer exists. Mitto's `settings.json` and
  `workspaces.json` must both point to the `.venv` binary. Mitto only reads
  config at startup — restart the service AND create a new session to pick up
  path changes.

[acp-log]: ACP_ISSUES_LOG.md
[memory index]: pykoclaw/.memory/INDEX.md
[plugin-config-env-file.md]: .memory/plugin-config-env-file.md
[reference links]: https://spec.commonmark.org/0.31.2/#reference-link
[plugin-config-env-file.md]: .memory/plugin-config-env-file.md
[session-resume-retry.md]: .memory/session-resume-retry.md
[session-resume-system-prompt.md]: .memory/session-resume-system-prompt.md
[claude-sdk-setting-sources.md]: .memory/claude-sdk-setting-sources.md
[slack-reply-extraction.md]: .memory/slack-reply-extraction.md
[worktree workflow docs]: docs/worktree-workflow.md

## Code Exploration with dora

This codebase uses dora for fast code intelligence and architectural analysis.

### IMPORTANT: Use dora for code exploration

**ALWAYS use dora commands for code exploration instead of Grep/Glob/Find.**

### All Commands

**Overview:**

- `dora status` - Check index health, file/symbol counts, last indexed time
- `dora map` - Show packages, file count, symbol count

**Files & Symbols:**

- `dora ls [directory] [--limit N] [--sort field]` - List files in directory with metadata (symbols, deps, rdeps). Default limit: 100
- `dora file <path>` - Show file's symbols, dependencies, and dependents
- `dora symbol <query> [--kind type] [--limit N]` - Find symbols by name across codebase. Default limit: 20
- `dora refs <symbol> [--kind type] [--limit N]` - Find all references to a symbol
- `dora exports <path>` - List exported symbols from a file
- `dora imports <path>` - Show what a file imports

**Dependencies:**

- `dora deps <path> [--depth N]` - Show file dependencies (what this imports). Default depth: 1
- `dora rdeps <path> [--depth N]` - Show reverse dependencies (what imports this). Default depth: 1
- `dora adventure <from> <to>` - Find shortest dependency path between two files

**Code Health:**

- `dora leaves [--max-dependents N]` - Find files with few/no dependents. Default: 0
- `dora lost [--limit N]` - Find unused exported symbols. Default limit: 50
- `dora treasure [--limit N]` - Find most referenced files and files with most dependencies. Default: 10

**Architecture Analysis:**

- `dora cycles [--limit N]` - Detect circular dependencies. Empty = good. Default: 50
- `dora coupling [--threshold N]` - Find bidirectionally dependent file pairs. Default threshold: 5
- `dora complexity [--sort metric]` - Show file complexity metrics (sort by: complexity, symbols, stability). Default: complexity

**Change Impact:**

- `dora changes <ref>` - Show files changed since git ref and their impact
- `dora graph <path> [--depth N] [--direction type]` - Generate dependency graph. Direction: deps, rdeps, both. Default: both, depth 1

**Documentation:**

- `dora docs [--type TYPE]` - List all documentation files. Use --type to filter by md or txt
- `dora docs search <query> [--limit N]` - Search through documentation content. Default limit: 20
- `dora docs show <path> [--content]` - Show document metadata and references. Use --content to include full text

**Note:** To find where a symbol/file is documented, use `dora symbol` or `dora file` which show a `documented_in` field.

**Database:**

- `dora schema` - Show database schema (tables, columns, indexes)
- `dora cookbook show [recipe]` - Query patterns with real examples (quickstart, methods, references, exports)
- `dora query "<sql>"` - Execute read-only SQL query against the database

### When to Use Other Tools

- **Read**: For reading file source code
- **Grep**: Only for non-code files or when dora fails
- **Edit/Write**: For making changes
- **Bash**: For running commands/tests

### Quick Workflow

```bash
dora status                      # Check index health
dora treasure                    # Find core files
dora file <path>                 # Understand a file
dora deps/rdeps <path>           # Navigate dependencies
dora symbol <query>              # Find symbols (shows documented_in)
dora refs <symbol>               # Find references
dora docs                        # List all documentation
dora docs search <query>         # Search documentation content
```

For detailed usage and examples, refer to `./dora/docs/SKILL.md`.
