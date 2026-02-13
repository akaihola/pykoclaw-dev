# Plugin Framework Learnings

## Architecture
- pykoclaw uses Click groups for CLI, Pydantic Settings for config, SQLite with `CREATE TABLE IF NOT EXISTS`
- No migration framework — plugins provide raw SQL via `get_db_migrations()`
- Entry point group: `pykoclaw.plugins`

## Patterns
- `importlib.metadata.entry_points(group=...)` returns all registered entry points
- Protocol + `@runtime_checkable` allows duck-typing check without inheritance
- `PykoClawPluginBase` provides no-op defaults so plugins only override what they need

## Integration Point
- Plugin loading happens in `main()` Click group callback, before subcommand dispatch
- `run_db_migrations()` called immediately after `_get_db_and_data_dir()`
- `register_commands()` receives the Click group to add subcommands dynamically

## Working Directory
- All `uv run` commands must run from `/home/akaihola/prg/pykoclaw/pykoclaw` (where pyproject.toml is)
