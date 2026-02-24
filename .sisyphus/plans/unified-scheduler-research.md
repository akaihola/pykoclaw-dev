# Unified Scheduler Service (Research)

## Status: Backlog

## Priority: 8

## TL;DR

> **Quick Summary**: Research feasibility of running a single pykoclaw scheduler
> service that manages tasks across all workspaces, instead of one scheduler
> service per workspace (currently: pipsa, tyko, väinö, and soon coleaders).
>
> **Deliverables**:
>
> - Feasibility analysis with pros/cons
> - Architecture proposal (if feasible)
> - Migration path from per-workspace schedulers
>
> **Estimated Effort**: Short
> **Depends On**: —

---

## Context

### Current State

Each pykoclaw workspace runs its own `pykoclaw scheduler` systemd service:
- `pykoclaw-scheduler-pipsa` (PYKOCLAW_DATA=/home/agent/pipsa)
- `pykoclaw-scheduler-tyko` (PYKOCLAW_DATA=/home/agent/my-knowledge)
- `pykoclaw-scheduler-vaino` (PYKOCLAW_DATA=/home/agent/paivi)
- (planned) `pykoclaw-scheduler-coleaders` (PYKOCLAW_DATA=/home/agent/coleaders)

Each polls its own `pykoclaw.db` for due tasks every 60 seconds.

### Why This Matters

As the number of workspaces grows, the number of systemd services grows linearly.
A unified scheduler could reduce operational complexity — one process, one config,
one set of logs to monitor.

### Key Questions to Answer

1. **DB access**: Can one scheduler poll multiple SQLite databases? Or do we need
   a shared DB?
2. **Workspace isolation**: Each workspace currently has its own CWD and CLAUDE.md.
   How would a unified scheduler maintain per-workspace context?
3. **Resource contention**: Would concurrent task dispatch across workspaces cause
   CCM queue pressure?
4. **Failure isolation**: Currently a crash in one scheduler doesn't affect others.
   Would unification create a single point of failure?
5. **Configuration**: How would the unified scheduler discover workspaces? Static
   config vs. auto-discovery?

---

## Work Objectives

### Core Objective

Determine whether unifying scheduler services is worth the effort, and if so,
propose a concrete architecture.

### Research Areas

- Survey current scheduler code (`pykoclaw scheduler` command)
- Identify coupling points between scheduler and workspace config
- Prototype multi-DB polling (if promising)
- Compare operational overhead: N services vs 1 service with N DB connections

---

## Verification Strategy

- Research spike documented in `.sisyphus/notepads/unified-scheduler`
- Decision recorded: proceed with implementation plan OR close as "not worth it"
