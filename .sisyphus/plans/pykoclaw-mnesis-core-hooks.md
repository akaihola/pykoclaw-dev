# Pykoclaw Mnesis Plugin — Minimal Core Hook Specification

## Status: Backlog

## Priority: 13

## TL;DR

> **Quick Summary**: Define the exact minimal core contract needed by
> `pykoclaw-mnesis`. Core provides **one dataclass** and **one plugin hook**.
> Everything else is plugin-side. No `mnesis` imports in core. No harness types
> in the hook API. Failures in plugin hooks must be non-fatal.
>
> **Estimated Effort**: Short
> **Depends On**: pykoclaw-mnesis-plugin
>
> Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-16T11-22-48-347Z_d187a71b-08d1-4f82-8c17-4ad375439d48.jsonl

---

## Guiding Principle

**Core is the contract. Plugin is the implementation.**

If a capability can be implemented in `pykoclaw-mnesis`, it **must** be
implemented there. Core provides only the narrowest possible hook surface.

---

## Current State

The plugin protocol supports:

- CLI commands
- MCP servers
- DB migrations
- Config classes
- Response transformation
- System prompt additions

**Missing**: observation of completed agent turns in a normalized,
backend-independent way.

---

## Proposed Core Contract

### Dataclass (core-owned, normalized)

```python
# plugins.py
from dataclasses import dataclass, field
from typing import Any

@dataclass(frozen=True, slots=True)
class CompletedTurn:
    """Normalized representation of a completed user/assistant turn.

    Deliberately free of harness-specific types. Survives backend changes.
    """
    conversation_name: str
    channel_prefix: str
    cwd: str
    user_text: str
    assistant_text: str
    session_id: str | None = None
    system_prompt_hash: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
```

### Plugin protocol addition

```python
# plugins.py
class PykoClawPlugin(Protocol):
    ...
    def on_completed_turn(self, db: DbConnection, turn: CompletedTurn) -> None:
        """Called after a turn completes. Failures are logged, not propagated."""
        ...

class PykoClawPluginBase:
    ...
    def on_completed_turn(self, db: DbConnection, turn: CompletedTurn) -> None:
        pass  # default no-op
```

---

## Emission Point (core only)

Location: `/home/agent/prg/pykoclaw-dev/pykoclaw/src/pykoclaw/agent_core.py`

After final assistant response assembled:

```python
# After streaming completes, before yielding final result
turn = CompletedTurn(
    conversation_name=conversation_name,
    channel_prefix=parse_channel_prefix(conversation_name),
    cwd=str(conv_dir),
    user_text=prompt,
    assistant_text=full_response_text,
    session_id=session_id,
    system_prompt_hash=sp_hash,
)

plugins = load_plugins()
for plugin in plugins:
    try:
        plugin.on_completed_turn(db, turn)
    except Exception:
        log.exception("Completed-turn hook failed in %s", type(plugin).__name__)
        # Non-fatal: continue to next plugin
```

---

## Exact Minimal File Changes

### `plugins.py` (+20 lines)

Add:

- `CompletedTurn` dataclass
- `on_completed_turn()` protocol method
- No-op default in `PykoClawPluginBase`

### `agent_core.py` (+15 lines)

Add:

- `CompletedTurn` construction after final response
- Defensive plugin dispatch loop

**Total core diff: ~35 lines. No imports of `mnesis`. No channel-plugin changes. No messaging-layer changes for phase 1.**

### Must-not guardrails

This hook work must **not**:

- add any `mnesis` import to core
- expose `claude_agent_sdk` types in the hook signature
- require changes in channel plugins or ACP-specific code paths
- persist plugin-owned memory data in core tables
- introduce prompt augmentation in the same change

---

## Failure Policy

Plugin hook failures **must not** affect the main response path:

- Wrap each plugin call in try/except
- Log exceptions at ERROR level
- Continue to next plugin
- Never retry or mutate the user-visible response

---

## Data Constraints

### Must include

- Stable Pykoclaw conversation identity
- Normalized text content
- Advisory harness session reference
- System prompt hash for continuity detection

### Must NOT include

- `claude_agent_sdk` message objects
- Raw stream chunks
- Provider-specific reasoning traces
- Tool call internals (unless already normalized)

---

## Future Extension (Deferred)

A bounded prompt augmentation hook may be added later if phase 3 proceeds:

```python
@dataclass(frozen=True, slots=True)
class PromptAugmentationContext:
    conversation_name: str
    channel_prefix: str
    cwd: str
    user_text: str
    session_id: str | None = None

def get_prompt_addition(self, db: DbConnection, ctx: PromptAugmentationContext) -> str | None: ...
```

**This is explicitly not required for phase 1.**

---

## Acceptance Criteria

- [ ] Exactly one new dataclass in core: `CompletedTurn`
- [ ] Exactly one new plugin hook: `on_completed_turn()`
- [ ] No `mnesis` imports in core
- [ ] No `claude_agent_sdk` types in hook signature
- [ ] Hook emitted once per completed turn
- [ ] Plugin hook failures are non-fatal and logged
- [ ] Existing behavior unchanged when no plugin implements hook

---

## Verification

- Unit test: `CompletedTurn` construction from agent response
- Unit test: hook dispatch with success
- Unit test: hook dispatch with failure (non-fatal)
- Integration test: plugin receives hook, records data
- Regression test: existing dispatch flow unchanged

---

## Backend Compatibility

This hook must remain valid when `claude_agent_sdk` is extracted into a backend
plugin. The payload is Pykoclaw-normalized and free of harness-specific types.

---

Pi-Session: d187a71b-08d1-4f82-8c17-4ad375439d48
Pi-Session-Slug: 2026-03-16T11-22-48-347Z_d187a71b
Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-16T11-22-48-347Z_d187a71b-08d1-4f82-8c17-4ad375439d48.jsonl
Pi-Session-Name: (unset)
