# Pykoclaw Mnesis Plugin — Phase 1 Implementation Plan

## Status: Backlog

## Priority: 12

## TL;DR

> **Quick Summary**: Implement phase 1 of `pykoclaw-mnesis` as a **plugin-only**
> sidecar memory system. Core changes are limited to **one minimal hook** that
> emits normalized completed-turn events. All recording, storage, compaction,
> and retrieval logic lives in the plugin package. The plugin does **not** change
> Claude session resume, prompt assembly, or dispatch behavior. Phase 1 proves
> Pykoclaw can own durable memory before adding any prompt augmentation.
>
> **Everything possible is done in the plugin. Core is the contract; plugin is
> the implementation.**
>
> **Estimated Effort**: Medium
> **Depends On**: pykoclaw-mnesis-plugin
>
> Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-16T11-22-48-347Z_d187a71b-08d1-4f82-8c17-4ad375439d48.jsonl

---

## Scope

### In scope

- create `pykoclaw-mnesis` package (all logic here)
- define normalized memory event model (plugin-owned, core-exposed via hook)
- **minimal core change**: add `CompletedTurn` dataclass + `on_completed_turn()` hook
- record turns in plugin-owned storage
- expose MCP retrieval tools from plugin memory
- keep current Claude session resume unchanged

### Out of scope (deliberately excluded)

- prompt augmentation (deferred to phase 3)
- summary injection into active prompts
- replacing harness-managed context
- sub-agent-only expansion policies
- global/shared memory spaces
- harness JSONL bootstrap beyond optional backfill helpers

### Must-not guardrails

Phase 1 must **not**:

- add more than the minimal contract hook surface to core
- introduce plugin-specific conditionals into channel plugins
- move retrieval or compaction logic into `/home/agent/prg/pykoclaw-dev/pykoclaw/`
- modify current session resume decision logic in `/home/agent/prg/pykoclaw-dev/pykoclaw-messaging/`
- require harness logs for normal operation
- make prompt contents larger unless and until a later prompt-augmentation phase is approved

---

## Architecture: Core is the Contract, Plugin is the Implementation

```
┌─────────────────────────────────────────┐
│  pykoclaw core                          │
│  ┌────────────────────────────────────┐ │
│  │  query_agent() / dispatch          │ │
│  │  ├─ Claude session resume/stream  │ │
│  │  └─ emit CompletedTurn ────────────┼─┼────┐
│  └────────────────────────────────────┘ │    │
│           ↑ minimal hook only          │    │
└───────────┼────────────────────────────┘    │
            │                                 │
            ↓                                 │
┌─────────────────────────────────────────┐   │
│  pykoclaw-mnesis plugin                 │   │
│  ├─ normalize/adapter layer            │←──┘
│  ├─ recorder (turn → storage)          │
│  ├─ compaction/summaries via mnesis    │
│  ├─ retrieval MCP tools                │
│  └─ config, schema, DB (plugin-owned)  │
└─────────────────────────────────────────┘
```

**Rule**: If it can be done in the plugin, it **must** be done in the plugin.
Core only provides the hook emission point. No `mnesis` imports in core.

---

## Deliverables

### New package (all implementation lives here)

```
pykoclaw-mnesis/
├── pyproject.toml
└── src/pykoclaw_mnesis/
    ├── __init__.py              # plugin entry
    ├── plugin.py                # PykoClawPlugin impl
    ├── config.py                # settings
    ├── models.py                # normalized plugin-side models
    ├── adapter.py               # mnesis wrapper / normalization
    ├── recorder.py              # turn ingestion
    ├── compaction.py            # background summarization
    ├── retrieval.py             # MCP tool implementations
    └── tests/
```

### Minimal core touchpoints (contract only)

- `plugins.py`: add `CompletedTurn` dataclass, `on_completed_turn()` protocol
- `agent_core.py`: emit hook after final response assembled

**No other core files. No core dependency on `mnesis`.**

---

## Work Breakdown

### Task 1 — Define minimal core hook (contract)

Files: `/home/agent/prg/pykoclaw-dev/pykoclaw/src/pykoclaw/plugins.py`

Add:

```python
@dataclass(frozen=True, slots=True)
class CompletedTurn:
    conversation_name: str
    channel_prefix: str
    cwd: str
    user_text: str
    assistant_text: str
    session_id: str | None = None
    system_prompt_hash: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
```

Add to `PykoClawPlugin`:

```python
def on_completed_turn(self, db: DbConnection, turn: CompletedTurn) -> None: ...
```

Default in `PykoClawPluginBase`: no-op pass.

### Task 2 — Emit hook from core

File: `/home/agent/prg/pykoclaw-dev/pykoclaw/src/pykoclaw/agent_core.py`

After final response assembled:

- construct `CompletedTurn`
- call `on_completed_turn()` for each plugin with exception handling
- log failures, never fail the main path

### Task 3 — Scaffold plugin package

Create `/home/agent/prg/pykoclaw-dev/pykoclaw-mnesis/` with:

- `pyproject.toml` with entry point
- plugin class implementing `on_completed_turn()`
- config surface for enable/disable

### Task 4 — Implement plugin recorder

In plugin:

- adapter layer receives `CompletedTurn`
- persists to plugin-owned storage (via `mnesis` or wrapper)
- maintains conversation identity mapping

### Task 5 — Implement retrieval tools

In plugin:

- `mnesis_grep` / `mnesis_describe` / `mnesis_expand` MCP tools
- bounded outputs
- safe no-op when no memory exists

### Task 6 — ADR

Write and land `/home/agent/prg/pykoclaw-dev/docs/adr/003-pykoclaw-mnesis-architecture.md`
capturing:

- core-is-contract, plugin-is-implementation principle
- harness-agnostic memory requirement
- hybrid-first approach
- minimal core changes policy
- explicit must-not decisions around `mnesis` imports in core and harness logs as source of truth

### Task 7 — Tests

- core hook tests: emission, failure handling, no regression
- plugin tests: recording, retrieval, compaction triggers
- integration: plugin loads, records, tools work

---

## Acceptance Criteria

- [ ] **Core changes ≤ 50 lines** across `plugins.py` + `agent_core.py`
- [ ] `pykoclaw-mnesis` exists as workspace package with all logic
- [ ] Plugin can be disabled; zero functional change to current behavior
- [ ] `mnesis` imports **only** in plugin, never in core
- [ ] Retrieval tools operate on plugin-owned memory
- [ ] Claude session resume unchanged
- [ ] ADR merged documenting architecture decisions

---

## Verification

- Unit tests in `pykoclaw-mnesis/tests/`
- Core hook tests in `pykoclaw/tests/`
- Existing dispatch/messaging tests pass unchanged
- Smoke test: real conversation, plugin enabled, tools return recorded data

---

## Guiding Principle

> **Core is the contract. Plugin is the implementation. If it can be done in
> the plugin, it must be done in the plugin.**

This keeps Pykoclaw core minimal, backend-agnostic, and easy to reason about.
The memory layer becomes an optional, evolvable subsystem rather than a core
entanglement.

---

## Related

- ADR: `docs/adr/003-pykoclaw-mnesis-architecture.md`
- Core hooks spec: `pykoclaw-mnesis-core-hooks.md`
- Strategic direction: `pykoclaw-mnesis-plugin.md`
- Memory note: `.memory/memory-canonical-vs-harness-logs.md`

---

Pi-Session: d187a71b-08d1-4f82-8c17-4ad375439d48
Pi-Session-Slug: 2026-03-16T11-22-48-347Z_d187a71b
Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-16T11-22-48-347Z_d187a71b-08d1-4f82-8c17-4ad375439d48.jsonl
Pi-Session-Name: (unset)
