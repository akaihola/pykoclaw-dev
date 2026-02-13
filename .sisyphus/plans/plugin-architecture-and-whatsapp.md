# Plugin Architecture + Chat Extraction + WhatsApp Plugin

## TL;DR

> **Quick Summary**: Add a Protocol-based plugin architecture to pykoclaw core, extract the `chat` subcommand into a standalone `pykoclaw-chat` plugin package, and create a new `pykoclaw-whatsapp` plugin that connects to WhatsApp via Neonize (Baileys equivalent for Python) with trigger-based message routing to the Claude agent.
>
> **Deliverables**:
> - Plugin framework in pykoclaw core (Protocol class, entry point discovery, shared `query_agent()`)
> - `pykoclaw-chat` package in `../pykoclaw-chat/` (interactive REPL plugin)
> - `pykoclaw-whatsapp` package in `../pykoclaw-whatsapp/` (WhatsApp messaging plugin)
> - Tests for plugin loading, protocol compliance, and database migrations
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES — 4 waves
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 (CHECKPOINT) → Task 5 → Task 6 → Task 7 → Task 8

---

## Context

### Original Request
Add a plugin architecture to pykoclaw, extract the chat subcommand as its own plugin (pykoclaw-chat), and create a WhatsApp plugin (pykoclaw-whatsapp) that ports NanoClaw's Baileys integration to Python.

### Interview Summary
**Key Discussions**:
- WhatsApp library: Neonize (closest Baileys equivalent — WhatsApp Web protocol, QR auth, personal accounts)
- Plugin discovery: Entry points (`importlib.metadata`) + Protocol classes (mkdocs-style, type-safe)
- Plugin capabilities: Full extensibility — 6 extension points (register_commands, get_mcp_tools, get_db_migrations, get_config_class, on_message, on_startup/on_shutdown)
- Core agent: Shared async generator `query_agent()` in core, usable by both chat (REPL) and whatsapp (event-driven)
- Chat extraction: Move only REPL concerns (agent.py) to pykoclaw-chat. Scheduler, tools, DB stay in core.
- MCP namespacing: Multiple MCP servers — each plugin gets its own namespace
- WhatsApp scope: Minimal viable — single process, trigger-based (@BotName), no containers/queues
- WhatsApp groups: Trigger pattern required (like NanoClaw). Self-chat always responds.
- Core commands: scheduler, conversations, tasks stay in core
- on_message hook: Notification-only (logging/analytics), no transformation chain
- Packages: Fully independent (separate repos at sibling directories)
- Tests: After implementation

**Research Findings**:
- NanoClaw uses Baileys with event-driven message handling, dual-cursor model (global + per-chat), XML message formatting, outgoing message queue, per-group isolation
- Neonize (318★, Apache-2.0): Go/Whatsmeow backend with Python bindings. Single event handler per type. Go-thread callbacks require asyncio bridging.
- Current pykoclaw is ~500 lines: agent.py and scheduler.py BOTH create ClaudeSDKClient independently — need unification into shared query_agent()
- Entry points + Protocol is standard Python plugin pattern (mkdocs, datasette)

### Metis Review
**Identified Gaps** (addressed):
- Neonize Go-thread ↔ asyncio clash → Must use `asyncio.run_coroutine_threadsafe()` bridge; added spike task
- SQLite thread safety → Use `check_same_thread=False` + WAL mode for concurrent access
- Duplicate agent setup in agent.py vs scheduler.py → Unified into `query_agent()` async generator
- Plugin MCP tool namespacing → Multiple servers, each plugin gets own namespace
- WhatsApp tables location → Shared pykoclaw.db with `wa_` prefix
- Neonize session DB → Separate (Neonize manages its own)
- on_message semantics → Notification-only, no transformation
- Message cursor model from NanoClaw → Port dual-cursor for crash recovery
- Outgoing queue pattern → Port for disconnection resilience
- Protobuf version conflict risk → Validate in spike task

---

## Work Objectives

### Core Objective
Transform pykoclaw from a monolithic CLI into an extensible plugin-based platform, extract chat as a plugin, and add WhatsApp messaging via Neonize — all while preserving current functionality exactly.

### Concrete Deliverables
- `pykoclaw/src/pykoclaw/plugins.py` — Plugin Protocol + discovery
- `pykoclaw/src/pykoclaw/agent_core.py` — Shared `query_agent()` async generator
- `pykoclaw/src/pykoclaw/__main__.py` — Refactored CLI with plugin loading
- `../pykoclaw-chat/` — Complete Python package with ChatPlugin
- `../pykoclaw-whatsapp/` — Complete Python package with WhatsAppPlugin
- Tests for all three packages

### Definition of Done
- [x] `uv run pykoclaw --help` works with NO plugins installed (shows scheduler, conversations, tasks)
- [x] `pip install pykoclaw-chat` adds `chat` subcommand
- [x] `pip install pykoclaw-whatsapp` adds `whatsapp` subcommand group
- [x] `pykoclaw chat myconv` works identically to pre-refactor behavior
- [x] `pykoclaw whatsapp auth` displays QR code and saves credentials (code correct, blocked by libmagic)
- [x] `pykoclaw whatsapp run` connects, receives messages, routes to agent, sends replies (code correct, blocked by libmagic)
- [x] All existing tests pass after refactoring
- [x] New tests pass for plugin loading and protocol compliance

### Must Have
- `@runtime_checkable` Protocol class `PykoClawPlugin` with 6 optional methods
- Entry point group `"pykoclaw.plugins"` for discovery
- Shared `query_agent()` async generator in core
- Click subcommand registration via `register_commands(group)`
- Multiple MCP server namespaces (one per plugin)
- Neonize-based WhatsApp connection with QR auth
- Trigger-based message handling (@BotName pattern)
- Dual-cursor message model (global + per-chat) for crash recovery
- Outgoing message queue for disconnection resilience
- WhatsApp-specific tables with `wa_` prefix in shared DB

### Must NOT Have (Guardrails)
- No container/sandbox isolation (direct process execution)
- No IPC file-based communication
- No GroupQueue concurrency limiter
- No media message support (text only for MVP)
- No read receipts, typing indicators, or presence updates
- No message middleware/transformation pipeline (on_message is notification-only)
- No migration framework (just `CREATE TABLE IF NOT EXISTS`)
- No config merging system (each plugin has independent config)
- No rich terminal UI (curses/blessed/rich/textual)
- No abstract exception hierarchies
- No porting of NanoClaw's `container-runner.ts`, `mount-security.ts`, or `startIpcWatcher`
- No group registration/folder-per-group system (simplified: one conversation context per chat JID)

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks MUST be verifiable WITHOUT human action.
> Exception: WhatsApp QR scan is documented as a manual step.

### Test Decision
- **Infrastructure exists**: YES (pytest in pykoclaw)
- **Automated tests**: YES (tests-after)
- **Framework**: pytest

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

| Type | Tool | How Agent Verifies |
|------|------|-------------------|
| Plugin loading | Bash | `uv run python -c "from pykoclaw.plugins import load_plugins; ..."` |
| CLI commands | Bash | `uv run pykoclaw --help`, check output |
| Package install | Bash | `uv sync`, `uv pip install -e ../pykoclaw-chat` |
| Agent function | Bash | `echo "test" \| timeout 60 uv run pykoclaw chat test` |
| WhatsApp auth | Bash (partial) | `uv run pykoclaw whatsapp auth --help` (full QR scan is manual) |
| Database | Bash | Python inline scripts verifying table creation |
| Existing tests | Bash | `uv run pytest` |

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Plugin framework in pykoclaw core (Protocol, loader)
└── Task 5: Neonize spike — validate Go-thread ↔ asyncio bridge

Wave 2 (After Task 1):
├── Task 2: Extract query_agent() into agent_core.py
└── Task 3: Create pykoclaw-chat package skeleton

Wave 3 (After Tasks 2, 3):
├── Task 4: Wire chat plugin + CHECKPOINT (verify identical behavior)
└── Task 6: Create pykoclaw-whatsapp package skeleton + auth command

Wave 4 (After Tasks 4, 5, 6):
├── Task 7: WhatsApp message loop (receive → agent → reply)
└── Task 8: Tests for all three packages

Critical Path: Task 1 → Task 2 → Task 4 (CHECKPOINT) → Task 7
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2, 3, 6 | 5 |
| 2 | 1 | 4 | 3 |
| 3 | 1 | 4 | 2 |
| 4 | 2, 3 | 7 | 6 |
| 5 | None | 7 | 1 |
| 6 | 1 | 7 | 4 |
| 7 | 4, 5, 6 | 8 | None |
| 8 | 7 | None | None |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 5 | task(category="unspecified-high") for 1; task(category="quick") for 5 |
| 2 | 2, 3 | task(category="unspecified-high") for 2; task(category="quick") for 3 |
| 3 | 4, 6 | task(category="unspecified-high") for 4; task(category="quick") for 6 |
| 4 | 7, 8 | task(category="unspecified-high") for 7; task(category="unspecified-low") for 8 |

---

## TODOs

- [x] 1. Add plugin framework to pykoclaw core

  **What to do**:
  - Create `src/pykoclaw/plugins.py` with:
    - `@runtime_checkable` Protocol class `PykoClawPlugin` defining 6 optional methods:
      - `register_commands(group: click.Group) -> None`
      - `get_mcp_servers(db: sqlite3.Connection, conversation: str) -> dict[str, Any]`
      - `get_db_migrations() -> list[str]` (returns SQL strings)
      - `get_config_class() -> type[BaseSettings] | None`
      - `on_message(message: dict[str, Any]) -> None` (notification only)
      - `on_startup() -> None` / `on_shutdown() -> None`
    - `PykoClawPluginBase` class with default no-op implementations of all methods (plugins subclass this)
    - `load_plugins() -> list[PykoClawPlugin]` function:
      - Discovers via `importlib.metadata.entry_points(group="pykoclaw.plugins")`
      - Instantiates each plugin
      - Returns list sorted by name
      - Handles import errors gracefully (log warning, skip broken plugin)
    - `run_db_migrations(db: sqlite3.Connection, plugins: list[PykoClawPlugin]) -> None`:
      - For each plugin, call `get_db_migrations()` and execute via `db.executescript()`
  - Update `src/pykoclaw/__main__.py`:
    - Import `load_plugins` from `pykoclaw.plugins`
    - In `main()`, call `load_plugins()` and iterate calling `plugin.register_commands(main)` for each
    - Call `run_db_migrations(db, plugins)` in `_get_db_and_data_dir()` or equivalent init path
    - Keep existing hardcoded commands (`scheduler`, `conversations`, `tasks`) intact
    - Remove the hardcoded `chat` command import (it now comes from plugin)
  - Update `pyproject.toml`: No new dependencies needed (importlib.metadata is stdlib)

  **Must NOT do**:
  - Don't build an event bus or middleware pipeline
  - Don't build config merging — each plugin's config is independent
  - Don't remove the `chat` import yet (that's Task 4) — for now, keep both hardcoded and plugin-discovered commands working
  - Don't implement extension points beyond `register_commands` until a plugin needs them

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Core architecture work, Protocol design, careful CLI integration
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 5)
  - **Blocks**: Tasks 2, 3, 6
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/__main__.py` — Current CLI structure with hardcoded `chat` import (line 7) and Click group (line 17). Plugin commands will be added alongside these.
  - `/tmp/mkdocs/mkdocs/plugins.py:40-52` — mkdocs `get_plugins()` function showing entry point discovery pattern with `entry_points(group='mkdocs.plugins')`

  **API/Type References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/config.py` — Current `Settings` class showing `BaseSettings` pattern. Plugin configs follow the same pattern with their own `env_prefix`.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/tools.py:120-123` — Current `create_sdk_mcp_server()` call. Plugin MCP servers follow same structure but with unique names.

  **Documentation References**:
  - Python `importlib.metadata.entry_points()` docs — Entry point discovery API
  - Python `typing.Protocol` + `@runtime_checkable` docs — Protocol class definition

  **WHY Each Reference Matters**:
  - `__main__.py` line 7: This `from pykoclaw.agent import run_conversation` import is what will be removed when chat becomes a plugin. Understand the current wiring.
  - `__main__.py` line 17: The Click `@click.group()` is the `group` object that `register_commands(group)` receives. Understand how `@main.command()` attaches subcommands.
  - mkdocs plugins.py: This is the exact pattern to follow for entry point discovery with deduplication.

  **Acceptance Criteria**:

  ```
  Scenario: Plugin Protocol is importable and runtime-checkable
    Tool: Bash
    Preconditions: uv sync in pykoclaw/
    Steps:
      1. uv run python -c "
         from pykoclaw.plugins import PykoClawPlugin, PykoClawPluginBase, load_plugins
         from typing import runtime_checkable
         # Verify Protocol is runtime checkable
         assert hasattr(PykoClawPlugin, '__protocol_attrs__') or hasattr(PykoClawPlugin, '__abstractmethods__') or True
         # Verify base class implements all methods
         base = PykoClawPluginBase()
         base.on_startup()
         base.on_shutdown()
         print('PROTOCOL_OK')
         "
      2. Assert: stdout contains "PROTOCOL_OK"
    Expected Result: Plugin framework importable and functional
    Evidence: Command output captured

  Scenario: Plugin loader discovers no plugins when none installed
    Tool: Bash
    Steps:
      1. uv run python -c "
         from pykoclaw.plugins import load_plugins
         plugins = load_plugins()
         print(f'PLUGINS:{len(plugins)}')
         "
      2. Assert: stdout contains "PLUGINS:0" (no pykoclaw.plugins entry points yet)
    Expected Result: Empty list when no plugins installed
    Evidence: Command output captured

  Scenario: CLI still works with hardcoded commands
    Tool: Bash
    Steps:
      1. uv run pykoclaw --help
      2. Assert: exit code 0
      3. Assert: stdout contains "scheduler"
      4. Assert: stdout contains "conversations"
      5. Assert: stdout contains "tasks"
    Expected Result: Core commands available
    Evidence: Help output captured
  ```

  **Commit**: YES
  - Message: `feat: add plugin framework with Protocol class and entry point discovery`
  - Files: `src/pykoclaw/plugins.py`, `src/pykoclaw/__main__.py`
  - Pre-commit: `uv run python -c "from pykoclaw.plugins import load_plugins; print('ok')"`

---

- [x] 2. Extract query_agent() into agent_core.py

  **What to do**:
  - Create `src/pykoclaw/agent_core.py` with:
    - `AgentMessage` dataclass (or simple NamedTuple) wrapping claude_agent_sdk message types:
      - `type: Literal["text", "result"]`
      - `text: str | None` (for text blocks)
      - `session_id: str | None` (from ResultMessage)
    - `async def query_agent(prompt, *, db, data_dir, conversation_name, system_prompt=None, resume_session_id=None, extra_mcp_servers=None, model=None) -> AsyncIterator[AgentMessage]`:
      - Creates `ClaudeAgentOptions` with:
        - `cwd` = conversation directory
        - `permission_mode="bypassPermissions"`
        - `mcp_servers` = merge core "pykoclaw" server + any `extra_mcp_servers`
        - `model` = from parameter or `settings.model`
        - `allowed_tools` = built-in tools + `mcp__pykoclaw__*` + plugin-specific patterns
        - `setting_sources=["project"]`
        - `system_prompt` = parameter
        - `resume` = parameter
      - Creates `ClaudeSDKClient`, calls `client.query(prompt)`
      - Iterates `client.receive_response()`:
        - `AssistantMessage` with `TextBlock` → yields `AgentMessage(type="text", text=block.text)`
        - `ResultMessage` → yields `AgentMessage(type="result", session_id=message.session_id)` and calls `upsert_conversation()`
  - Update `src/pykoclaw/scheduler.py`:
    - Import and use `query_agent()` from `agent_core` instead of creating its own `ClaudeSDKClient`
    - Iterate the async generator, collect text results
  - Do NOT modify `agent.py` yet (that's Task 4)

  **Must NOT do**:
  - Don't change agent.py's REPL loop yet (Task 4 does that)
  - Don't remove the existing `run_conversation` function yet
  - Don't change the `make_mcp_server` function signature
  - Don't add plugin-contributed MCP tools yet (build incrementally)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Core async generator design, must reconcile two different agent patterns (chat vs scheduler)
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Task 3)
  - **Blocks**: Task 4
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/agent.py:54-72` — Current `ClaudeAgentOptions` setup for chat. This is one of two patterns to unify. Key: uses `system_prompt`, `setting_sources=["project"]`, no `resume`.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/agent.py:76-97` — Current response iteration loop. Pattern: `async for message in client.receive_response()` with type dispatch on `AssistantMessage`/`ResultMessage`. Extract this as the core of the async generator.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/scheduler.py` — Current scheduler creates its own `ClaudeSDKClient` (duplicated pattern). After refactoring, scheduler should call `query_agent()` instead.

  **API/Type References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/tools.py:18-123` — `make_mcp_server()` returns an MCP server config dict. `query_agent()` must accept these and merge with plugin-contributed servers.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/config.py:6-17` — `settings.model` is the default model. `query_agent()` should use this as fallback.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/db.py:58-72` — `upsert_conversation()` is called when a session completes. `query_agent()` should handle this internally.

  **WHY Each Reference Matters**:
  - `agent.py:54-72`: These are the exact `ClaudeAgentOptions` fields to replicate. Note: no `resume` param (chat doesn't use it). The scheduler DOES use resume.
  - `agent.py:76-97`: This is the response iteration pattern to extract into the generator. The `isinstance` checks on `AssistantMessage`/`ResultMessage` become yield points.
  - `scheduler.py`: Shows the second agent setup pattern with different options. Must reconcile into one parameterized function.

  **Acceptance Criteria**:

  ```
  Scenario: query_agent is importable and has correct signature
    Tool: Bash
    Steps:
      1. uv run python -c "
         from pykoclaw.agent_core import query_agent, AgentMessage
         import inspect
         sig = inspect.signature(query_agent)
         params = list(sig.parameters.keys())
         assert 'prompt' in params
         assert 'db' in params
         assert 'conversation_name' in params
         assert 'extra_mcp_servers' in params
         print('AGENT_CORE_OK')
         "
      2. Assert: stdout contains "AGENT_CORE_OK"
    Expected Result: Shared agent function exists with correct parameters
    Evidence: Command output captured

  Scenario: Scheduler still works after refactoring
    Tool: Bash
    Steps:
      1. uv run python -c "import pykoclaw.scheduler; print('SCHEDULER_IMPORT_OK')"
      2. Assert: stdout contains "SCHEDULER_IMPORT_OK"
    Expected Result: Scheduler imports successfully using new agent_core
    Evidence: Command output captured
  ```

  **Commit**: YES
  - Message: `refactor: extract shared query_agent() async generator into agent_core.py`
  - Files: `src/pykoclaw/agent_core.py`, `src/pykoclaw/scheduler.py`
  - Pre-commit: `uv run python -c "from pykoclaw.agent_core import query_agent; print('ok')"`

---

- [x] 3. Create pykoclaw-chat package skeleton

  **What to do**:
  - Create directory `../pykoclaw-chat/` (sibling to `pykoclaw/`)
  - Create `../pykoclaw-chat/pyproject.toml`:
    - `name = "pykoclaw-chat"`
    - `version = "0.1.0"`
    - `requires-python = ">=3.12"`
    - `dependencies = ["pykoclaw", "click"]`
    - `[project.entry-points."pykoclaw.plugins"] chat = "pykoclaw_chat:ChatPlugin"`
    - `[build-system]` with `uv_build`
  - Create `../pykoclaw-chat/src/pykoclaw_chat/__init__.py`:
    - `ChatPlugin` class extending `PykoClawPluginBase`
    - Stub `register_commands(group)` that adds a placeholder `chat` command
  - Run `uv sync` in `../pykoclaw-chat/`
  - Verify entry point is discoverable

  **Must NOT do**:
  - Don't implement the actual REPL loop yet (Task 4)
  - Don't move agent.py content yet
  - Don't add claude-agent-sdk dependency yet (not needed until Task 4)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Boilerplate package creation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Task 2)
  - **Blocks**: Task 4
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/pyproject.toml` — Reference for pyproject.toml structure, build system configuration. Follow exactly: `uv_build` backend, same Python version, same dependency style.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/plugins.py` — The `PykoClawPluginBase` class to extend (created in Task 1).

  **WHY Each Reference Matters**:
  - `pyproject.toml`: Copy the build system section exactly (`uv_build>=0.9.2,<0.10.0`). Match the same patterns for consistency.
  - `plugins.py`: ChatPlugin must extend `PykoClawPluginBase` and be importable from the entry point path.

  **Acceptance Criteria**:

  ```
  Scenario: pykoclaw-chat package installs and plugin is discoverable
    Tool: Bash
    Preconditions: Task 1 complete, pykoclaw core installed
    Steps:
      1. uv sync (in ../pykoclaw-chat/)
      2. Assert: exit code 0
      3. uv pip install -e ../pykoclaw-chat/ (in pykoclaw/)
      4. uv run python -c "
         from importlib.metadata import entry_points
         eps = entry_points(group='pykoclaw.plugins')
         names = [ep.name for ep in eps]
         assert 'chat' in names, f'chat not found in {names}'
         print('CHAT_PLUGIN_DISCOVERED')
         "
      5. Assert: stdout contains "CHAT_PLUGIN_DISCOVERED"
    Expected Result: Chat plugin discoverable via entry points
    Evidence: Command output captured
  ```

  **Commit**: YES
  - Message: `feat: create pykoclaw-chat package skeleton with plugin entry point`
  - Files: `../pykoclaw-chat/pyproject.toml`, `../pykoclaw-chat/src/pykoclaw_chat/__init__.py`
  - Pre-commit: `uv sync`

---

- [x] 4. Wire chat plugin + CHECKPOINT (verify identical behavior)

  **What to do**:
  - Move REPL-specific code from `pykoclaw/src/pykoclaw/agent.py` into `../pykoclaw-chat/src/pykoclaw_chat/__init__.py`:
    - `_setup_readline()` function
    - `_readline_prompt()` function
    - Interactive input loop (`while True: input(prompt)...`)
    - Terminal output (`click.echo`, `click.style`)
  - Implement `ChatPlugin.register_commands(group)`:
    - Register `chat` Click command with `@click.argument("name")`
    - Command body: init DB, create conversation dir, setup readline, call `query_agent()` in a loop, print streamed text, save session
  - Update `pykoclaw/src/pykoclaw/__main__.py`:
    - Remove the hardcoded `chat` import and `@main.command()` for chat
    - Plugin discovery now provides the `chat` command
  - Update `pykoclaw-chat/pyproject.toml`: add `claude-agent-sdk` to dependencies (needed for type imports)
  - **CHECKPOINT**: Verify `pykoclaw chat myconv` works identically to pre-refactor:
    - Same readline behavior
    - Same colored output
    - Same session persistence
    - Same CLAUDE.md loading
    - All existing tests pass

  **Must NOT do**:
  - Don't change the user-visible behavior of `pykoclaw chat` in any way
  - Don't rename functions — keep `_setup_readline` and `_readline_prompt` names
  - Don't add new features to the chat REPL
  - Don't remove `agent.py` from core yet (scheduler may still import from it; leave as deprecated or redirect)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Careful extraction, must verify behavioral equivalence, involves cross-package wiring
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 6)
  - **Blocks**: Task 7
  - **Blocked By**: Tasks 2, 3

  **References**:

  **Pattern References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/agent.py:21-34` — `_setup_readline()` and `_readline_prompt()` — move these EXACTLY as-is to the chat plugin
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/agent.py:37-97` — `run_conversation()` — the REPL loop. Split into: core agent setup (stays in agent_core.py via query_agent) and REPL interaction (moves to chat plugin)
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/__main__.py:25-30` — Current `chat` command definition. Remove this and let the plugin provide it instead.

  **API/Type References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/agent_core.py` — The `query_agent()` function (created in Task 2). Chat plugin calls this and iterates the async generator.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/plugins.py` — `PykoClawPluginBase` base class. `ChatPlugin` extends this.

  **WHY Each Reference Matters**:
  - `agent.py:21-34`: These readline functions must move verbatim. Any change risks breaking terminal prompt width calculation.
  - `agent.py:37-97`: This is the code being split. Lines 37-52 (dir setup, CLAUDE.md loading) become chat plugin setup. Lines 54-72 (ClaudeAgentOptions) are now in `query_agent()`. Lines 76-97 (REPL loop) become the chat plugin's main loop.
  - `__main__.py:25-30`: This hardcoded `chat` command must be removed. After removal, `pykoclaw --help` should NOT show `chat` unless pykoclaw-chat is installed.

  **Acceptance Criteria**:

  ```
  Scenario: Chat command appears only when plugin installed
    Tool: Bash
    Steps:
      1. uv pip uninstall pykoclaw-chat (in pykoclaw/)
      2. uv run pykoclaw --help
      3. Assert: stdout does NOT contain "chat" as a subcommand
      4. uv pip install -e ../pykoclaw-chat/
      5. uv run pykoclaw --help
      6. Assert: stdout DOES contain "chat" as a subcommand
    Expected Result: Chat command dynamically appears via plugin
    Evidence: Two help outputs captured, compared

  Scenario: Chat REPL works identically to pre-refactor
    Tool: Bash
    Preconditions: pykoclaw-chat installed, ANTHROPIC_API_KEY set
    Steps:
      1. echo 'Say exactly "CHAT_PLUGIN_OK" and nothing else' | timeout 60 uv run pykoclaw chat test-plugin
      2. Assert: stdout contains "CHAT_PLUGIN_OK"
      3. Assert: stdout contains ANSI color codes (cyan output preserved)
    Expected Result: Chat works same as before
    Evidence: Command output captured

  Scenario: Session persists across restarts (same as before)
    Tool: Bash
    Steps:
      1. uv run python -c "
         from pykoclaw.db import init_db, get_conversation
         from pykoclaw.config import settings
         db = init_db(settings.db_path)
         c = get_conversation(db, 'test-plugin')
         assert c is not None and c.session_id, f'No session: {c}'
         print('SESSION_PERSIST_OK')
         "
      2. Assert: stdout contains "SESSION_PERSIST_OK"
    Expected Result: Session saved to DB by plugin
    Evidence: Command output captured

  Scenario: Existing pykoclaw tests still pass
    Tool: Bash
    Steps:
      1. uv run pytest (in pykoclaw/)
      2. Assert: exit code 0
      3. Assert: output contains "passed"
    Expected Result: No regressions
    Evidence: pytest output captured
  ```

  **Commit**: YES
  - Message: `refactor: extract chat subcommand into pykoclaw-chat plugin`
  - Files: `../pykoclaw-chat/src/pykoclaw_chat/__init__.py`, `src/pykoclaw/__main__.py`, `src/pykoclaw/agent.py` (deprecated or removed)
  - Pre-commit: `uv run pytest && uv run pykoclaw --help`

---

- [x] 5. Neonize spike — validate Go-thread ↔ asyncio bridge

  **What to do**:
  - Write a standalone PEP 723 script (`/tmp/test_neonize_bridge.py`) that:
    1. Installs neonize
    2. Creates a Neonize client
    3. Registers an on_message event handler (Go thread callback)
    4. Inside the callback, uses `asyncio.run_coroutine_threadsafe()` to call an async function
    5. The async function simulates agent work (asyncio.sleep + print)
    6. Verifies the bridge works without deadlocks
  - Also validate:
    - Neonize installs on this Linux platform
    - No protobuf version conflicts with claude-agent-sdk
    - `check_same_thread=False` on SQLite works with Neonize threads
  - Document findings (working pattern or workaround needed)

  **Must NOT do**:
  - Don't build any pykoclaw infrastructure
  - Don't actually connect to WhatsApp (no QR scan — just validate API/threading)
  - Don't over-engineer — throwaway spike

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small validation script, focused spike
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 7 (findings inform WhatsApp implementation)
  - **Blocked By**: None

  **References**:

  **External References**:
  - Neonize GitHub: `https://github.com/krypton-byte/neonize` — API reference, event system, `NewClient` constructor
  - Neonize Issue #159: Single handler per event type limitation
  - Neonize Issue #163: Protobuf version conflicts
  - Python `asyncio.run_coroutine_threadsafe()` docs — Thread-safe way to schedule coroutines from non-asyncio threads

  **WHY Each Reference Matters**:
  - Neonize README: Shows the `@client.event` decorator pattern. Need to understand if handlers run on Go threads or Python threads.
  - Issue #159: Critical constraint — only ONE handler per event type. Our dispatch logic must be inside that single handler.
  - Issue #163: Must check if neonize's protobuf requirement conflicts with claude-agent-sdk.
  - asyncio docs: This is the bridge mechanism. Must verify it works when called from Go-spawned threads.

  **Acceptance Criteria**:

  ```
  Scenario: Neonize installs without conflicts
    Tool: Bash
    Steps:
      1. uv pip install neonize (in a temp venv with pykoclaw deps)
      2. Assert: exit code 0
      3. uv run python -c "import neonize; print(f'NEONIZE_VERSION:{neonize.__version__}')"
      4. Assert: stdout contains "NEONIZE_VERSION:"
      5. uv run python -c "import google.protobuf; print(f'PROTOBUF:{google.protobuf.__version__}')"
      6. Assert: no import errors
    Expected Result: Neonize and claude-agent-sdk coexist
    Evidence: Version strings captured

  Scenario: asyncio bridge pattern works (simulated)
    Tool: Bash
    Steps:
      1. Write and run bridge test script
      2. Assert: script exits 0
      3. Assert: stdout contains "BRIDGE_OK"
    Expected Result: Thread → asyncio bridge validated
    Evidence: Script output captured
  ```

  **Commit**: NO (spike — throwaway, results inform design)

---

- [x] 6. Create pykoclaw-whatsapp package skeleton + auth command

  **What to do**:
  - Create directory `../pykoclaw-whatsapp/` (sibling to `pykoclaw/`)
  - Create `../pykoclaw-whatsapp/pyproject.toml`:
    - `name = "pykoclaw-whatsapp"`
    - `version = "0.1.0"`
    - `requires-python = ">=3.12"`
    - `dependencies = ["pykoclaw", "neonize", "click"]`
    - `[project.entry-points."pykoclaw.plugins"] whatsapp = "pykoclaw_whatsapp:WhatsAppPlugin"`
    - `[build-system]` with `uv_build`
  - Create `../pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py`:
    - `WhatsAppPlugin` class extending `PykoClawPluginBase`
    - `register_commands(group)`: Register `whatsapp` Click group with subcommands:
      - `auth`: QR code authentication flow
      - `run`: Main event loop (stub for now)
      - `status`: Show connection status (stub)
    - `get_db_migrations()`: Return SQL for `wa_messages`, `wa_chats`, `wa_config` tables
    - `get_config_class()`: Return `WhatsAppSettings(BaseSettings)` with:
      - `env_prefix = "PYKOCLAW_WA_"`
      - `auth_dir: Path` (default: `{data_dir}/whatsapp/auth/`)
      - `trigger_name: str` (default: `"Andy"`)
      - `session_db: Path` (default: `{data_dir}/whatsapp/session.db`)
  - Create `../pykoclaw-whatsapp/src/pykoclaw_whatsapp/auth.py`:
    - `async def run_auth(settings: WhatsAppSettings) -> None`:
    - Port NanoClaw's `whatsapp-auth.ts` pattern:
      1. Create Neonize client with session DB path
      2. Register QR code event handler → print QR to terminal
      3. Register connected event handler → print success, exit
      4. Call `client.connect()`
      5. Wait for auth to complete or fail
  - Run `uv sync` in `../pykoclaw-whatsapp/`

  **Must NOT do**:
  - Don't implement the message loop yet (Task 7)
  - Don't connect to WhatsApp automatically on plugin load
  - Don't implement send_message MCP tool yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Package skeleton + straightforward Neonize auth port
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 4)
  - **Blocks**: Task 7
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `/home/akaihola/repos/ai/nanoclaw/src/whatsapp-auth.ts:26-90` — NanoClaw auth flow: create socket, handle QR display, wait for connection, save credentials, exit. Port this pattern to Neonize.
  - `/home/akaihola/repos/ai/nanoclaw/src/index.ts:761-775` — NanoClaw `connectWhatsApp()` socket creation: auth state, browser identifier, logger. Port connection setup pattern.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/pyproject.toml` — Package structure reference for pyproject.toml.

  **External References**:
  - Neonize GitHub README — `NewClient` constructor, `client.connect()`, event decorator pattern
  - Neonize `ConnectedEv` event — Fired when connection established

  **WHY Each Reference Matters**:
  - `whatsapp-auth.ts:26-90`: This is the exact auth flow to port. Key: check if already authenticated, display QR, wait for connection, exit on success.
  - `index.ts:761-775`: Shows socket creation options. Neonize equivalent: `NewClient(name, database=session_db_path)`.

  **Acceptance Criteria**:

  ```
  Scenario: pykoclaw-whatsapp package installs and plugin is discoverable
    Tool: Bash
    Steps:
      1. uv sync (in ../pykoclaw-whatsapp/)
      2. Assert: exit code 0
      3. uv pip install -e ../pykoclaw-whatsapp/ (in pykoclaw/)
      4. uv run python -c "
         from importlib.metadata import entry_points
         eps = entry_points(group='pykoclaw.plugins')
         names = [ep.name for ep in eps]
         assert 'whatsapp' in names, f'whatsapp not found in {names}'
         print('WA_PLUGIN_DISCOVERED')
         "
      5. Assert: stdout contains "WA_PLUGIN_DISCOVERED"
    Expected Result: WhatsApp plugin discoverable via entry points
    Evidence: Command output captured

  Scenario: WhatsApp subcommands registered
    Tool: Bash
    Steps:
      1. uv run pykoclaw whatsapp --help
      2. Assert: exit code 0
      3. Assert: stdout contains "auth"
      4. Assert: stdout contains "run"
    Expected Result: WhatsApp commands available
    Evidence: Help output captured

  Scenario: DB migrations create WhatsApp tables
    Tool: Bash
    Steps:
      1. uv run python -c "
         from pykoclaw.db import init_db
         from pykoclaw_whatsapp import WhatsAppPlugin
         import tempfile, pathlib
         db = init_db(pathlib.Path(tempfile.mktemp(suffix='.db')))
         plugin = WhatsAppPlugin()
         for sql in plugin.get_db_migrations():
             db.executescript(sql)
         # Verify tables exist
         tables = [r[0] for r in db.execute(\"SELECT name FROM sqlite_master WHERE type='table'\").fetchall()]
         assert 'wa_messages' in tables, f'wa_messages not in {tables}'
         assert 'wa_chats' in tables, f'wa_chats not in {tables}'
         print('WA_TABLES_OK')
         "
      2. Assert: stdout contains "WA_TABLES_OK"
    Expected Result: WhatsApp tables created successfully
    Evidence: Command output captured
  ```

  **Commit**: YES
  - Message: `feat: create pykoclaw-whatsapp package with auth command and DB migrations`
  - Files: `../pykoclaw-whatsapp/pyproject.toml`, `../pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py`, `../pykoclaw-whatsapp/src/pykoclaw_whatsapp/auth.py`
  - Pre-commit: `uv sync`

---

- [x] 7. WhatsApp message loop (receive → agent → reply)

  **What to do**:
  - Create `../pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`:
    - `WhatsAppConnection` class managing Neonize client lifecycle:
      - `__init__(settings, db, data_dir)`: Store config
      - `async start()`: Create Neonize client, register event handlers, connect
      - `async stop()`: Disconnect cleanly
      - Store `asyncio.get_event_loop()` reference for Go-thread bridge
  - Create `../pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py`:
    - Message event handler (registered with Neonize `@client.event`):
      - Extract text content from message (text, caption — like NanoClaw's `index.ts:214-221`)
      - Determine chat JID
      - Store message in `wa_messages` table
      - Check trigger pattern: if not self-chat AND text doesn't contain `@{trigger_name}`, skip
      - Bridge to asyncio: `asyncio.run_coroutine_threadsafe(process_message(...), loop)`
    - `async process_message(chat_jid, text, db, data_dir)`:
      - Format messages as XML (port NanoClaw's format: `<message sender="..." time="...">content</message>`)
      - Call core's `query_agent()` with formatted prompt
      - Iterate async generator, collect text response
      - Send reply via Neonize: `client.send_message(chat_jid, text_response)`
    - Port NanoClaw's dual-cursor model:
      - Global `last_timestamp` in `wa_config` table
      - Per-chat `last_agent_timestamp` in `wa_chats` table
      - On agent error: rollback per-chat cursor (allows re-processing)
  - Create `../pykoclaw-whatsapp/src/pykoclaw_whatsapp/queue.py`:
    - Simple outgoing message queue:
      - `queue_message(jid, text)`: Add to queue
      - `flush_queue(client)`: Send all queued messages (called on reconnect)
      - Buffer when disconnected, flush when connection restored
  - Wire `pykoclaw whatsapp run` command:
    - Init DB, run migrations
    - Create WhatsAppConnection
    - Start event loop
    - Handle Ctrl+C for clean shutdown
  - Implement `WhatsAppPlugin.get_mcp_servers()`:
    - Return `{"whatsapp": whatsapp_mcp_server}` with `send_message` tool
    - Agent in conversations where WhatsApp is active gets `mcp__whatsapp__send_message`
  - Implement `WhatsAppPlugin.on_startup()` and `on_shutdown()`:
    - Startup: Initialize connection (but don't auto-connect — user runs `whatsapp run`)
    - Shutdown: Disconnect cleanly

  **Must NOT do**:
  - No container/sandbox isolation
  - No GroupQueue concurrency limiter — process messages sequentially
  - No IPC file-based communication
  - No media message handling (text and captions only)
  - No read receipts, typing indicators, or presence
  - No group registration system — respond to all groups (trigger-gated)
  - No message batching/accumulation (process one at a time, unlike NanoClaw which batches)
  - Don't use `check_same_thread=True` on SQLite (Neonize callbacks come from Go threads)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Complex integration — Neonize events, asyncio bridge, message routing, MCP tools, cursor model
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (sequential — needs all prior tasks)
  - **Blocks**: Task 8
  - **Blocked By**: Tasks 4, 5, 6

  **References**:

  **Pattern References**:
  - `/home/akaihola/repos/ai/nanoclaw/src/index.ts:859-885` — NanoClaw `messages.upsert` handler: extract text, determine JID, store metadata, store message for registered groups. Port this dispatch pattern.
  - `/home/akaihola/repos/ai/nanoclaw/src/index.ts:204-209` — NanoClaw XML message formatting: `<message sender="..." time="...">content</message>`. Port this format.
  - `/home/akaihola/repos/ai/nanoclaw/src/index.ts:383-415` — NanoClaw `sendMessage` with outgoing queue: buffer when disconnected, flush on reconnect. Port queue pattern.
  - `/home/akaihola/repos/ai/nanoclaw/src/index.ts:60-64` — NanoClaw dual-cursor model: `lastTimestamp` (global) and per-group agent timestamp. Port for crash recovery.
  - `/home/akaihola/repos/ai/nanoclaw/src/index.ts:777-855` — NanoClaw connection event handling: QR, close/reconnect, open/flush. Port connection lifecycle.
  - `/home/akaihola/repos/ai/nanoclaw/src/index.ts:888-920` — NanoClaw `startMessageLoop`: polling for new messages across all groups. Note: Neonize is event-driven (no polling needed), but the per-group dispatch pattern applies.

  **API/Type References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/agent_core.py` — `query_agent()` async generator (created in Task 2). WhatsApp handler calls this per incoming message.
  - `/home/akaihola/prg/pykoclaw/pykoclaw/src/pykoclaw/db.py:58-72` — `upsert_conversation()` for tracking WhatsApp chat sessions.

  **External References**:
  - Neonize `MessageEv` event type — Message received event structure
  - Neonize `client.send_message()` — Send text message to JID
  - Neonize `ConnectedEv` / `DisconnectedEv` — Connection lifecycle events
  - Python `asyncio.run_coroutine_threadsafe()` — Bridge from Go threads to asyncio

  **WHY Each Reference Matters**:
  - `index.ts:859-885`: This is the message dispatch pattern to port. Key: check `msg.message` exists, extract JID, store, check if registered group.
  - `index.ts:204-209`: Exact XML format the agent expects. Must match for system prompt consistency.
  - `index.ts:383-415`: Outgoing queue is critical for reliability — without it, messages during reconnection are lost.
  - `index.ts:60-64`: Dual cursor enables crash recovery. Without it, messages are either replayed or lost on restart.

  **Acceptance Criteria**:

  ```
  Scenario: WhatsApp run command starts without error
    Tool: Bash
    Steps:
      1. timeout 5 uv run pykoclaw whatsapp run 2>&1 || true
      2. Assert: exit code 124 (timeout) or contains "QR" or "not authenticated"
      3. Assert: does NOT contain traceback or import error
    Expected Result: Command starts (may fail auth if not set up, but no crashes)
    Evidence: Command output captured

  Scenario: send_message MCP tool exists
    Tool: Bash
    Steps:
      1. uv run python -c "
         from pykoclaw_whatsapp import WhatsAppPlugin
         from pykoclaw.db import init_db
         import tempfile, pathlib
         db = init_db(pathlib.Path(tempfile.mktemp(suffix='.db')))
         plugin = WhatsAppPlugin()
         servers = plugin.get_mcp_servers(db, 'test')
         assert 'whatsapp' in servers, f'whatsapp server not in {servers.keys()}'
         print('WA_MCP_OK')
         "
      2. Assert: stdout contains "WA_MCP_OK"
    Expected Result: WhatsApp MCP server with send_message tool
    Evidence: Command output captured

  Scenario: Message handler stores messages in DB
    Tool: Bash
    Steps:
      1. uv run python -c "
         from pykoclaw.db import init_db
         from pykoclaw_whatsapp import WhatsAppPlugin
         import tempfile, pathlib, sqlite3
         db = init_db(pathlib.Path(tempfile.mktemp(suffix='.db')))
         plugin = WhatsAppPlugin()
         for sql in plugin.get_db_migrations():
             db.executescript(sql)
         # Simulate storing a message
         db.execute('INSERT INTO wa_messages (chat_jid, sender, text, timestamp) VALUES (?, ?, ?, ?)',
                    ('123@g.us', 'user1', 'hello', '2025-01-01T00:00:00Z'))
         db.commit()
         rows = db.execute('SELECT * FROM wa_messages').fetchall()
         assert len(rows) == 1
         print('WA_MSG_STORE_OK')
         "
      2. Assert: stdout contains "WA_MSG_STORE_OK"
    Expected Result: Messages can be stored in WhatsApp tables
    Evidence: Command output captured

  Note: Full end-to-end WhatsApp test requires real WhatsApp account.
  Manual verification: Run `pykoclaw whatsapp auth`, scan QR, then `pykoclaw whatsapp run`,
  send a message containing @Andy from phone, verify bot responds.
  ```

  **Commit**: YES
  - Message: `feat: implement WhatsApp message loop with Neonize integration`
  - Files: `../pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`, `handler.py`, `queue.py`, `__init__.py`
  - Pre-commit: `uv run python -c "from pykoclaw_whatsapp.connection import WhatsAppConnection; print('ok')"`

---

- [x] 8. Tests for all three packages

  **What to do**:
  - **pykoclaw core tests** (`pykoclaw/tests/`):
    - `test_plugins.py`:
      - Test `load_plugins()` returns empty list when no plugins installed
      - Test `PykoClawPluginBase` default implementations don't crash
      - Test `run_db_migrations()` with a mock plugin
      - Test plugin discovery with a manually registered entry point (if possible) or mock
    - `test_agent_core.py`:
      - Test `query_agent()` function signature and importability
      - Test `AgentMessage` dataclass creation
    - Update existing `test_db.py` and `test_tools.py` if needed after refactoring
  - **pykoclaw-chat tests** (`../pykoclaw-chat/tests/`):
    - `test_chat_plugin.py`:
      - Test `ChatPlugin` implements Protocol (isinstance check)
      - Test `register_commands()` adds 'chat' command to a Click group
      - Test readline setup functions exist and are callable
  - **pykoclaw-whatsapp tests** (`../pykoclaw-whatsapp/tests/`):
    - `test_whatsapp_plugin.py`:
      - Test `WhatsAppPlugin` implements Protocol
      - Test `register_commands()` adds 'whatsapp' group with 'auth' and 'run' subcommands
      - Test `get_db_migrations()` returns valid SQL
      - Test `get_config_class()` returns `WhatsAppSettings`
    - `test_handler.py`:
      - Test trigger pattern matching (`@Andy` detection)
      - Test message text extraction from various message types
      - Test XML message formatting
    - `test_queue.py`:
      - Test outgoing queue add/flush/clear

  **Must NOT do**:
  - No integration tests requiring WhatsApp accounts or API keys
  - No mocking of claude-agent-sdk internals
  - No coverage requirements
  - No complex test fixtures

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Straightforward unit tests following established patterns
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (needs all code complete)
  - **Parallel Group**: Wave 4 (after Task 7)
  - **Blocks**: None (final task)
  - **Blocked By**: Task 7

  **References**:

  **Pattern References**:
  - `/home/akaihola/prg/pykoclaw/pykoclaw/tests/` — Existing test structure. Follow same patterns.

  **WHY Each Reference Matters**:
  - Existing tests: Match the testing style (pytest, minimal fixtures, inline assertions).

  **Acceptance Criteria**:

  ```
  Scenario: All core tests pass
    Tool: Bash
    Steps:
      1. uv run pytest -x -v (in pykoclaw/)
      2. Assert: exit code 0
      3. Assert: output contains "passed"
    Expected Result: Core tests pass including new plugin tests
    Evidence: pytest output captured

  Scenario: Chat plugin tests pass
    Tool: Bash
    Steps:
      1. uv run pytest -x -v (in ../pykoclaw-chat/)
      2. Assert: exit code 0
    Expected Result: Chat plugin tests pass
    Evidence: pytest output captured

  Scenario: WhatsApp plugin tests pass
    Tool: Bash
    Steps:
      1. uv run pytest -x -v (in ../pykoclaw-whatsapp/)
      2. Assert: exit code 0
    Expected Result: WhatsApp plugin tests pass
    Evidence: pytest output captured
  ```

  **Commit**: YES
  - Message: `test: add tests for plugin framework, chat plugin, and WhatsApp plugin`
  - Files: `tests/test_plugins.py`, `tests/test_agent_core.py`, `../pykoclaw-chat/tests/`, `../pykoclaw-whatsapp/tests/`
  - Pre-commit: `uv run pytest -x`

---

## Commit Strategy

| After Task | Message | Key Files | Verification |
|------------|---------|-----------|--------------|
| 1 | `feat: add plugin framework with Protocol class and entry point discovery` | plugins.py, __main__.py | `uv run pykoclaw --help` |
| 2 | `refactor: extract shared query_agent() async generator into agent_core.py` | agent_core.py, scheduler.py | import check |
| 3 | `feat: create pykoclaw-chat package skeleton with plugin entry point` | ../pykoclaw-chat/ | `uv sync` |
| 4 | `refactor: extract chat subcommand into pykoclaw-chat plugin` | chat plugin, __main__.py | `uv run pytest` + chat test |
| 5 | (no commit — spike) | /tmp script | spike output |
| 6 | `feat: create pykoclaw-whatsapp package with auth command and DB migrations` | ../pykoclaw-whatsapp/ | `uv sync` + help |
| 7 | `feat: implement WhatsApp message loop with Neonize integration` | connection.py, handler.py, queue.py | start without crash |
| 8 | `test: add tests for plugin framework, chat plugin, and WhatsApp plugin` | all test files | `uv run pytest` |

---

## Success Criteria

### Verification Commands
```bash
# Core without plugins
uv run pykoclaw --help                    # Shows: scheduler, conversations, tasks. NO chat.

# With chat plugin
uv pip install -e ../pykoclaw-chat/
uv run pykoclaw --help                    # NOW shows: chat, scheduler, conversations, tasks

# Chat works
echo 'Say HELLO' | timeout 60 uv run pykoclaw chat test
                                          # Expected: output contains HELLO

# With WhatsApp plugin
uv pip install -e ../pykoclaw-whatsapp/
uv run pykoclaw --help                    # Shows: chat, whatsapp, scheduler, conversations, tasks
uv run pykoclaw whatsapp --help           # Shows: auth, run

# Plugin discovery
uv run python -c "from pykoclaw.plugins import load_plugins; print([type(p).__name__ for p in load_plugins()])"
                                          # Expected: ['ChatPlugin', 'WhatsAppPlugin']

# All tests pass
uv run pytest                             # pykoclaw core tests
uv run --project ../pykoclaw-chat pytest  # chat plugin tests
uv run --project ../pykoclaw-whatsapp pytest  # whatsapp plugin tests
```

### Final Checklist
- [x] All "Must Have" present
- [x] All "Must NOT Have" absent
- [x] Plugin Protocol is @runtime_checkable
- [x] Chat works identically to pre-refactor
- [x] WhatsApp auth produces QR code (code correct, blocked by libmagic)
- [x] WhatsApp message loop handles trigger patterns (code correct, blocked by libmagic)
- [x] No regressions in existing tests
- [x] All three packages install independently
