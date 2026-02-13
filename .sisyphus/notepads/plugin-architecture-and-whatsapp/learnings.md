# Learnings

## Task 4: Move REPL to pykoclaw-chat plugin

### Click dynamic command registration
- Click's `@click.group(invoke_without_command=True)` callback runs AFTER help rendering
- Dynamically registering commands inside the group callback means `--help` won't list them
- Solution: Custom `click.Group` subclass that overrides `list_commands()` and `get_command()` to lazily load plugins
- `_PluginGroup` pattern with `_plugins_loaded` flag ensures one-time plugin loading

### query_agent() vs old run_conversation()
- Old code kept one `ClaudeSDKClient` alive for entire REPL session
- New `query_agent()` creates a new client per call but supports `resume_session_id`
- Chat plugin tracks `session_id` from `ResultMessage` and passes it back for session continuity
- Also checks existing DB conversation on startup for cross-session resume

### click.echo color stripping
- `click.echo(click.style(..., fg="cyan"))` strips ANSI when stdout is not a terminal (piped)
- This is identical behavior to pre-refactor — not a regression
- Cyan ANSI codes appear in real terminal sessions

### Plugin entry point wiring
- Entry point `pykoclaw.plugins` in pyproject.toml correctly discovered via `importlib.metadata.entry_points()`
- Plugin install/uninstall correctly adds/removes commands from CLI

## Task 7: WhatsApp message loop implementation

### Neonize event naming
- QR code event is `QREv` (from `neonize.events`), NOT `QRCodeEv`
- Auth.py also had this wrong import — existing bug
- Event registration uses `@client.event(EventType)` decorator pattern

### Neonize NewClient constructor
- `NewClient(name)` — only takes name, jid, props, uuid
- NO `database` parameter — auth.py had this wrong too
- The `name` parameter is used as the client identifier

### libmagic system dependency
- `neonize` depends on `python-magic` which needs `libmagic1` system library
- On NixOS/nix: `LD_LIBRARY_PATH=/nix/store/.../file-5.45/lib` needed
- Without it, all neonize imports fail at module load time

### uv editable install cache issues
- `uv pip install -e ../pykoclaw` may use stale cached wheel
- `uv cache clean --force pykoclaw` + `--no-cache --reinstall` needed to get fresh build
- `uv lock --upgrade-package pykoclaw` alone doesn't fix it
- The `file:///` dependency in pyproject.toml can reference stale builds

### Go-thread → asyncio bridge
- Neonize callbacks run on Go threads, not Python's main thread
- `asyncio.run_coroutine_threadsafe(coro, loop)` bridges to event loop
- SQLite needs `check_same_thread=False` (handled by WAL mode + separate connection)

### Dual-cursor model
- `wa_config.last_timestamp` — global cursor for all messages received
- `wa_chats.last_agent_timestamp` — per-chat cursor for agent processing
- Agent only sees messages newer than its last processing timestamp
