# Configurable Kernel Instructions File Paths

## Status: Backlog
## Priority: 10

## TL;DR

> **Quick Summary**: At session start, AGENTS.md says to read `SOUL.md`,
> `USER.md`, and daily memory files — but pykoclaw never does this automatically.
> The agent bootstraps without any workspace personality, long-term memory, or
> user context unless it happens to read those files explicitly mid-session.
>
> Add a workspace config key (`kernel_files`) containing an ordered list of
> file paths (relative to workspace root, or absolute) to auto-load into the
> system prompt at the start of every session. Default:
> `AGENTS.md`, `SOUL.md`, `USER.md`, `memory/MEMORY.md`.
>
> **Estimated Effort**: Short
> **Depends On**: (none)

---

## Motivation

`AGENTS.md` instructs the agent to read several files before doing anything
else each session. In practice, Claude Code injects `AGENTS.md` and `CLAUDE.md`
via its own file-watching mechanism, but pykoclaw sessions (scheduler tasks,
Matrix/WhatsApp conversations) start cold — they get none of the workspace
personality files unless the system prompt is explicitly constructed to include
them.

The result is an agent that:
- Has no memory of past decisions
- Doesn't know who it's talking to (USER.md)
- Has no personality or values (SOUL.md)
- Repeats mistakes MEMORY.md was supposed to prevent

Auto-loading these files at session start closes the gap without requiring the
agent to waste a turn reading files it always needs.

## Expected Outcome

- Workspace config supports a `kernel_files` key (ordered list of paths)
- Pykoclaw reads each listed file at startup and prepends contents to the
  system prompt (clearly delimited, e.g. `## <filename>\n<content>\n---`)
- Missing files are silently skipped (not every workspace has SOUL.md)
- Default list applied when `kernel_files` is not set:
  `["AGENTS.md", "SOUL.md", "USER.md", "memory/MEMORY.md", "memory/%Y-%m-%d.md"]`
- Paths relative to workspace root (`MITTO_DIR` or equivalent); absolute
  paths also accepted
- Config is workspace-specific — different agents (tyko, vaino, pipsa) can
  have different kernel file lists

## Implementation Sketch

### Config (`.env` or `pykoclaw.toml` in workspace)

```ini
# Ordered list, colon-separated or JSON array
KERNEL_FILES=AGENTS.md:SOUL.md:USER.md:memory/MEMORY.md
```

Or in a future TOML config:

```toml
[agent]
kernel_files = ["AGENTS.md", "SOUL.md", "USER.md", "memory/MEMORY.md"]
```

### Loader (new helper, e.g. `pykoclaw/src/pykoclaw/kernel.py`)

Paths are expanded through `datetime.strftime()` before resolution, so any
`strftime` format code is valid (`%Y`, `%m`, `%d`, `%H`, etc.). This handles
daily memory files naturally without a custom placeholder syntax.

```python
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_KERNEL_FILES = [
    "AGENTS.md",
    "SOUL.md",
    "USER.md",
    "memory/MEMORY.md",
    "memory/%Y-%m-%d.md",
]

def load_kernel_files(
    workspace: Path,
    paths: list[str],
    *,
    now: datetime | None = None,
) -> str:
    """Read kernel files and return them as a concatenated string.

    Paths are expanded with strftime before resolution, so format codes like
    %Y, %m, %d produce date-stamped filenames at load time.  Expansion uses
    the OS local time so the date matches what the user sees on their machine.
    Missing files are silently skipped.
    """
    if now is None:
        now = datetime.now().astimezone()  # local time with local tz
    sections = []
    for template in paths:
        rel = now.strftime(template)
        p = Path(rel) if Path(rel).is_absolute() else workspace / rel
        if p.exists():
            sections.append(f"## {rel}\n\n{p.read_text()}\n")
    return "\n---\n\n".join(sections)
```

### Integration points

- **Scheduler** (`scheduler.py`): prepend kernel block to `system_prompt`
  before calling `query_agent()`
- **ACP server** (`server.py`): prepend to system prompt injected at
  `session/new`
- **WhatsApp / Matrix plugins**: pass through from pykoclaw core (system prompt
  construction should be centralised, not per-plugin)

### Config resolution order

1. Explicit `KERNEL_FILES` env var in workspace `.env`
2. `kernel_files` in `pykoclaw.toml` (if that config format is adopted)
3. Hardcoded default list

## Open Questions

- Should the kernel block be prepended before or after the base system prompt
  (the one in workspace `CLAUDE.md`)? Likely after — CLAUDE.md is the frame;
  kernel files are the memory layer.
- The `now` parameter on `load_kernel_files` exists for testing only (inject a
  fixed `datetime` to make tests deterministic). Production always calls
  `datetime.now().astimezone()` to get OS local time, so `%Y-%m-%d` resolves
  to the date the user sees on their machine — no per-workspace timezone config
  needed.

## Related

- [session-resume-across-restarts.md] — Complementary: this feature fills the
  kernel; session resume fills the conversation history.
- [harness-agnostic-backend.md] — If pykoclaw gains a harness-agnostic layer,
  kernel file loading belongs there.

[session-resume-across-restarts.md]: session-resume-across-restarts.md
[harness-agnostic-backend.md]: harness-agnostic-backend.md
