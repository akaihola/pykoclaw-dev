# Plugin Config .env File Resolution

**Tags:** config, gotcha, pydantic-settings, env
**Related:** [channel-dispatch.md], [workspace-layout.md]

Plugin `Settings` classes hardcode `~/.local/share/pykoclaw/.env` in their
`model_config["env_file"]`. This breaks when `PYKOCLAW_DATA` points elsewhere.

**Fix pattern:** resolve the data dir from `PYKOCLAW_DATA` env var at import
time and include it in the env_file tuple:

```python
import os
_DEFAULT_DATA = Path.home() / ".local" / "share" / "pykoclaw"
def _resolve_data_dir() -> Path:
    return Path(os.environ.get("PYKOCLAW_DATA", str(_DEFAULT_DATA)))

model_config = {
    "env_file": (
        str(_resolve_data_dir() / ".env"),   # PYKOCLAW_DATA/.env
        str(_DEFAULT_DATA / ".env"),          # default location
        ".env",                               # cwd
    ),
}
```

**Note:** pykoclaw-whatsapp still has the hardcoded-only path — same bug,
not yet fixed.

[channel-dispatch.md]: channel-dispatch.md
[workspace-layout.md]: workspace-layout.md
