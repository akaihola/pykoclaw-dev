# Pykoclaw Mnesis Plugin — Strategic Direction

## Status: Backlog

## Priority: 11

## TL;DR

> **Quick Summary**: Add a new `pykoclaw-mnesis` plugin that provides
> harness-agnostic, append-only memory for long-running agent sessions. **Core
> provides only minimal normalized hooks; all implementation lives in the
> plugin.** Use `mnesis` as the engine substrate, but Pykoclaw owns the
> canonical memory model. Start as a **hybrid sidecar** (recording + retrieval
> without replacing Claude resume). Harness session files may be used for
> bootstrap/audit only, never as source of truth.
>
> **Core principle**: If it can be done in the plugin, it **must** be done in
> the plugin.
>
> **Estimated Effort**: Large
> **Depends On**: (none — but aligns with harness-agnostic-backend)
>
> Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-16T11-22-48-347Z_d187a71b-08d1-4f82-8c17-4ad375439d48.jsonl

---

## Core Principle: Core is the Contract, Plugin is the Implementation

**Everything possible is done in `pykoclaw-mnesis`.**

Core changes are limited to:

- defining the `CompletedTurn` normalized dataclass (the contract)
- emitting the `on_completed_turn()` hook (the call)
- (future) bounded prompt augmentation hook

All recording, storage, compaction, summarization, and retrieval logic lives in
the plugin. This keeps core minimal, backend-agnostic, and future-proof.

---

## Research Summary

Based on investigation of:

- LCM paper (`papers.voltropy.com/LCM`)
- `Lucenor/mnesis` — mature Python LCM implementation
- `dddabtc/lcm-prototype` — concept sketch only
- `Martian-Engineering/lossless-claw` — OpenClaw integration reference
- HN discussion on LCM
- Pykoclaw's current Claude SDK architecture

### What LCM is

Lossless Context Management separates:

1. **Immutable history** — append-only store of original messages
2. **Active context** — budgeted view potentially containing summaries

Key LCM ideas worth preserving:

- append-only storage
- hierarchical summary DAGs with provenance
- soft/hard compaction thresholds
- deterministic fallback for summarization failure
- retrieval/expansion tools over compacted history

---

## Decision

### Adopt plugin-only architecture

Implement `pykoclaw-mnesis` as a **new plugin package** with:

- `mnesis` or thin wrapper as the engine substrate
- Pykoclaw-owned normalized memory model at boundaries
- **minimal core plugin-mechanism changes** (contract only)
- hybrid sidecar operation in phase 1

### Explicit non-goals for phase 1

- **No** replacement of Claude Code session resume
- **No** harness JSON/JSONL as source of truth
- **No** immediate new core agent backend abstraction
- **No** rewriting prompt assembly through external context engine
- **No** coupling to one harness's session format

### Must-not guardrails

This work must **not**:

- add `mnesis` as a dependency of `/home/agent/prg/pykoclaw-dev/pykoclaw/pyproject.toml`
- import `mnesis` anywhere under `/home/agent/prg/pykoclaw-dev/pykoclaw/src/pykoclaw/`
- expose `claude_agent_sdk` types in plugin hooks or plugin-facing models
- require channel plugins to implement separate memory logic per channel
- make message persistence depend on Claude Code/OpenClaw/Pi session-log availability
- change existing dispatch, streaming, or resume semantics when the plugin is disabled
- require DB schema changes in core for phase 1 unless absolutely unavoidable and separately justified

### Source-of-truth rule

Harness session files (Claude Code JSONL, OpenClaw logs, future Pi logs) may be
used **only** for:

- optional bootstrap/backfill
- crash recovery
- audit/debug

Canonical source of truth must remain Pykoclaw-controlled normalized records.

---

## Why `mnesis`

- Python-native, matches Pykoclaw stack
- append-only SQLite store
- summary DAG persistence
- context assembly logic
- compaction engine with deterministic fallback
- tool-output tombstoning
- BYO-LLM mode for externally managed turns

Not a drop-in, but a strong substrate behind a plugin adapter layer.

---

## Phased Approach

### Phase 0 — Research + Design Stabilization

- confirm minimal core hook set
- define normalized turn schema
- ADR documenting architecture

**Deliverable**: approved ADR + hook specification

### Phase 1 — Sidecar Memory Recording + Retrieval

**Core changes**: ≤ 50 lines (hook dataclass + emission)

**Plugin deliverables**:

- package scaffold
- config + enablement
- normalized turn recorder
- persistent memory DB via `mnesis`
- MCP retrieval tools

**Constraint**: no change to current agent turn semantics

### Phase 2 — Background Summarization

- configurable thresholds
- compaction / summary DAG
- observability tooling

### Phase 3 — Optional Bounded Prompt Augmentation

- bounded memory capsule injection
- no hidden full-context rewriting
- A/B or staged rollout

### Phase 4 — Evaluate Deeper Context Ownership

Decision gate: remain hybrid or move toward external context assembly?

---

## Minimal Core Changes (Contract Only)

### New in `plugins.py`

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

class PykoClawPlugin(Protocol):
    ...
    def on_completed_turn(self, db: DbConnection, turn: CompletedTurn) -> None: ...

class PykoClawPluginBase:
    ...
    def on_completed_turn(self, db: DbConnection, turn: CompletedTurn) -> None:
        pass
```

### Emission in `agent_core.py`

After final response assembled, wrap in defensive try/except, log failures,
never break main path.

**That's it.** Everything else is plugin-side.

---

## Architecture Diagram

```textn pykoclaw core (contract only)
  ┌────────────────────────────────────┐
  │ query_agent() / dispatch            │
  │ ├─ Claude session resume/stream   │
  │ └─ emit CompletedTurn ─────────────┼─┐
  └────────────────────────────────────┘ │
          ↑ minimal hook only            │
  ────────┼──────────────────────────────┘
          │
  ┌───────┴──────────────────────────────┐
  │ pykoclaw-mnesis plugin               │
  │ ├─ normalize/adapter                 │
  │ ├─ recorder (turn → storage)         │
  │ ├─ compaction/summaries via mnesis   │
  │ ├─ retrieval MCP tools               │
  │ └─ config, schema, DB (plugin-owned)│
  └──────────────────────────────────────┘
```

---

## Related Plans

- Phase 1 implementation: `pykoclaw-mnesis-plugin-phase1.md`
- Core hooks spec: `pykoclaw-mnesis-core-hooks.md`
- ADR: `docs/adr/003-pykoclaw-mnesis-architecture.md`
- Memory note: `.memory/memory-canonical-vs-harness-logs.md`

---

## Risks

- Plugin hook set may be awkward for clean ingestion → solve by minimizing core scope
- `mnesis` abstractions may not map perfectly → solved by adapter layer in plugin
- Model may underuse retrieval tools → solved by later prompt augmentation
- Over-coupling to `mnesis` internals → prevented by Pykoclaw-owned normalized boundary

---

## Definition of Done

- [ ] `pykoclaw-mnesis` plugin package exists (all logic here)
- [ ] Core changes limited to minimal contract hooks
- [ ] `mnesis` imports **only** in plugin
- [ ] Retrieval tools work against plugin-owned memory
- [ ] Claude session resume unchanged
- [ ] Plugin disable = zero functional change
- [ ] ADR merged documenting core-is-contract principle

---

Pi-Session: d187a71b-08d1-4f82-8c17-4ad375439d48
Pi-Session-Slug: 2026-03-16T11-22-48-347Z_d187a71b
Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-16T11-22-48-347Z_d187a71b-08d1-4f82-8c17-4ad375439d48.jsonl
Pi-Session-Name: (unset)
