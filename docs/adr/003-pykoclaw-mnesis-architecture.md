# ADR 003: Pykoclaw Mnesis Memory Plugin Architecture

- Status: Proposed
- Date: 2026-03-16
- Deciders: Pykoclaw maintainers
- Technical Story: Introduce durable, harness-agnostic memory without expanding core responsibility
- Pi-Session: d187a71b-08d1-4f82-8c17-4ad375439d48
- Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-16T11-22-48-347Z_d187a71b-08d1-4f82-8c17-4ad375439d48.jsonl

## Context

Pykoclaw currently relies on harness-managed session memory, especially through
Claude Code session resume. This provides practical continuity but ties memory
behavior to a specific harness and does not give Pykoclaw first-class ownership
of durable conversation memory.

We want a memory layer that:

- survives long-running and cross-restart conversations
- remains valid if we support multiple harnesses
- remains valid if we move away from Claude Code
- does not bloat `pykoclaw` core with memory-engine concerns

Research covered the LCM paper, `mnesis`, `lcm-prototype`, `lossless-claw`,
and Pykoclaw’s existing architecture.

Key findings:

- `mnesis` is the strongest reusable Python implementation substrate.
- `lossless-claw` is a good integration reference, especially for retrieval and
  compaction lifecycle ideas, but is tightly coupled to OpenClaw.
- Harness session JSON/JSONL files are useful for bootstrap, audit, and crash
  recovery, but are a poor canonical memory substrate because they are
  harness-format-specific and future-hostile.

## Decision

We will implement durable memory as a new plugin package,
`pykoclaw-mnesis`, with only minimal required changes in `pykoclaw` core.

### The core architectural rule

Core is the contract. Plugin is the implementation.

If a capability can be implemented in `pykoclaw-mnesis`, it must be
implemented there rather than in `pykoclaw` core.

### What core will do

Core will only:

- define a normalized completed-turn contract (`CompletedTurn`)
- emit a completed-turn plugin hook (`on_completed_turn()`)
- optionally, in a later phase, expose a bounded prompt-augmentation hook

### What the plugin will do

`pykoclaw-mnesis` will own:

- all `mnesis` imports and integration code
- normalized turn recording adapter
- memory storage, summaries, and compaction
- retrieval and expansion MCP tools
- plugin config and migrations
- optional bootstrap/backfill helpers

## Status of current harness behavior

The initial rollout will be hybrid.

We will keep current Claude session resume behavior unchanged in phase 1.
The memory plugin supplements current behavior; it does not replace harness
memory ownership in the first iteration.

## Explicit architectural decisions

### 1. Canonical memory is Pykoclaw-owned and normalized

Canonical durable memory must be represented in a Pykoclaw-controlled,
normalized form. It must not depend on the shape of Claude Code, OpenClaw,
Pi, or other harness session logs.

### 2. Harness logs are not source of truth

Harness session files may be used only for:

- bootstrap/backfill
- crash recovery
- audit/debug

Harness session files must not be treated as the canonical memory substrate.

### 3. `mnesis` stays out of core

`mnesis` must not be imported into `pykoclaw` core. It belongs exclusively in
`pykoclaw-mnesis`.

### 4. Minimal core changes are mandatory

The acceptable phase-1 core changes are intentionally tiny and should be
confined to the minimum practical set of files.

### 5. No harness-specific types in plugin hooks

Plugin hooks must expose normalized Pykoclaw-owned models, not
`claude_agent_sdk` objects or other harness-specific message types.

## Consequences

### Positive

- Core stays small and backend-agnostic
- Memory remains portable across future harness changes
- Plugin can evolve independently
- Plugin can be disabled without changing current behavior
- Clear separation between contract and implementation

### Negative

- Adds one new cross-package contract to maintain
- Some functionality will be deferred to later phases to keep core minimal
- Hybrid mode means phase 1 will not capture the full upside of external
  context ownership yet

## Rejected alternatives

### Make harness JSON/JSONL the source of truth

Rejected because it tightly couples memory to one harness format and weakens
future multi-harness portability.

### Import `mnesis` directly into core

Rejected because it would enlarge core responsibility and entangle the core
package with a specific memory engine.

### Replace current session resume immediately

Rejected for phase 1 because it is a much larger architectural change and is
not required to prove the value of plugin-owned memory.

## Implementation notes

This ADR is implemented in backlog planning via:

- `/home/agent/prg/pykoclaw-dev/.sisyphus/plans/pykoclaw-mnesis-plugin.md`
- `/home/agent/prg/pykoclaw-dev/.sisyphus/plans/pykoclaw-mnesis-plugin-phase1.md`
- `/home/agent/prg/pykoclaw-dev/.sisyphus/plans/pykoclaw-mnesis-core-hooks.md`
- `/home/agent/prg/pykoclaw-dev/.memory/memory-canonical-vs-harness-logs.md`

## References

- LCM paper: https://papers.voltropy.com/LCM
- `mnesis`: https://github.com/Lucenor/mnesis
- `lossless-claw`: https://github.com/Martian-Engineering/lossless-claw
- `lcm-prototype`: https://github.com/dddabtc/lcm-prototype
