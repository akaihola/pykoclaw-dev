# Plugin System

**Tags:** architecture, plugins
**Related:** [channel-dispatch.md], [workspace-layout.md]

Plugins are discovered via `importlib.metadata.entry_points(group="pykoclaw.plugins")`.

Each plugin implements `PykoClawPlugin` protocol or extends `PykoClawPluginBase`:

- `register_commands(group)` — add Click CLI commands
- `get_mcp_servers(db, conversation)` — return MCP server dicts for the agent
- `get_db_migrations()` — return SQL strings executed on startup
- `get_config_class()` — return a Pydantic Settings subclass
- `native_file_extensions()` — file suffixes the channel can deliver natively
- `transform_response(text, ctx)` — post-process agent reply text
- `get_system_prompt_addition()` — return a paragraph to append to the agent
  system prompt, or `None` to add nothing. Use this to inject formatting
  conventions that the agent must follow (e.g. always use full file paths).

**Composing system prompt additions:**

```python
from pykoclaw.plugins import compose_system_prompt_additions, load_plugins
all_plugins = load_plugins()
addition = compose_system_prompt_additions(all_plugins)  # str | None
```

Channel plugins (`WhatsAppConnection`, `MatrixConnection`) accept
`system_prompt_addition: str | None` in their constructors and append it
to the system prompt built by `_build_system_prompt()`.

Registered in `pyproject.toml`:

```toml
[project.entry-points."pykoclaw.plugins"]
myplugin = "my_package:MyPlugin"
```

The `_PluginGroup` Click group in `__main__.py` lazy-loads plugins on first
command resolution, ensuring DB migrations run before any plugin command.

[channel-dispatch.md]: channel-dispatch.md
[workspace-layout.md]: workspace-layout.md
