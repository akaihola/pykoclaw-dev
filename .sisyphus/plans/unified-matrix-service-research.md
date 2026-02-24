# Unified Matrix Service (Research)

## Status: Backlog

## Priority: 8

## TL;DR

> **Quick Summary**: Research feasibility of running a single pykoclaw Matrix
> service that handles multiple workspaces via agent routing, similar to how
> the WhatsApp service already supports multi-agent routing via `agent-routes.json`.
>
> **Deliverables**:
>
> - Feasibility analysis with pros/cons
> - Architecture proposal (if feasible)
> - Comparison with WhatsApp multi-agent routing approach
>
> **Estimated Effort**: Short
> **Depends On**: —

---

## Context

### Current State

The WhatsApp gateway already supports multi-agent routing: a single
`pykoclaw-whatsapp` service dispatches to multiple agents based on
`agent-routes.json`. Different WhatsApp groups route to different agents
(Ressu, Tyko, Väinö), each with their own data directory, DB, and personality.

The Matrix gateway does **not** have this. Currently there's only one Matrix
service: `pykoclaw-matrix-tyko` (my-knowledge/Tyko). If we wanted to add
a Matrix-connected Coleaders agent, we'd need a second Matrix service with
a second Matrix account.

### Why This Matters

As more agents need Matrix access, having per-agent Matrix services means:
- N Matrix accounts (N logins, N device verifications, N E2EE key stores)
- N systemd services
- N processes consuming resources

A unified Matrix service with routing (like WhatsApp) would mean:
- 1 Matrix account
- 1 systemd service
- Room-to-agent routing via config file

### Key Questions to Answer

1. **Matrix account model**: Can one Matrix account join rooms for multiple agents?
   Or do different agents need different display names per room?
2. **Display name**: WhatsApp uses `[AgentName]:` prefix in multi-agent groups.
   Matrix could do the same, or use display name changes per room (if supported).
3. **Architecture alignment**: How much of the WhatsApp routing code can be
   shared or extracted into `pykoclaw-messaging`?
4. **E2EE implications**: Does multi-agent routing affect E2EE key management?
5. **Back-compat**: Can we migrate the existing Tyko Matrix setup non-disruptively?

---

## Work Objectives

### Core Objective

Determine whether the WhatsApp-style multi-agent routing pattern can be applied
to the Matrix gateway, and if so, propose a concrete architecture.

### Research Areas

- Compare WhatsApp routing.py with Matrix connection.py
- Identify what routing abstractions could be shared
- Test Matrix display name per-room capabilities
- Evaluate E2EE impact
- Prototype room-to-agent config

---

## Verification Strategy

- Research spike documented in `.sisyphus/notepads/unified-matrix`
- Decision recorded: proceed with implementation plan OR close as "not worth it"
