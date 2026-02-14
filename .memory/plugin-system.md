# Plugin System

**Tags:** architecture, plugins
**Related:** [channel-dispatch.md], [workspace-layout.md]

Plugins are discovered via `importlib.metadata.entry_points(group="pykoclaw.plugins")`.

Each plugin implements `PykoClawPlugin` protocol or extends `PykoClawPluginBase`:
- `register_commands(group)` — add Click CLI commands
- `get_mcp_servers(db, conversation)` — return MCP server dicts for the agent
- `get_db_migrations()` — return SQL strings executed on startup
- `get_config_class()` — return a Pydantic Settings subclass

Registered in `pyproject.toml`:
```toml
[project.entry-points."pykoclaw.plugins"]
myplugin = "my_package:MyPlugin"
```

The `_PluginGroup` Click group in `__main__.py` lazy-loads plugins on first
command resolution, ensuring DB migrations run before any plugin command.

[channel-dispatch.md]: channel-dispatch.md
[workspace-layout.md]: workspace-layout.md
