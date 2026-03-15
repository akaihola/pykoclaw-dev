# Mitto Shared MCP Port Ownership

## Status: Backlog

## Priority: 4

## TL;DR

> **Quick Summary**: Multiple Mitto systemd instances (`mitto-web`, `mitto-web-testi`, `mitto-paivi`) currently all try to bind the default MCP HTTP port `127.0.0.1:5757`. In practice `mitto-paivi` wins and the other instances log `Failed to start MCP server ... address already in use` on every restart. Decide whether one instance should exclusively own the shared MCP listener or whether each instance should run with its own MCP port / MCP disabled.
>
> **Deliverables**:
>
> - Confirm intended MCP topology for all Mitto instances
> - Document the expected owner of `127.0.0.1:5757`, or assign per-instance ports
> - Update the relevant user services under `/home/agent/.config/systemd/user/`
> - Verify restarts no longer emit spurious MCP bind warnings
>
> **Estimated Effort**: Short
> **Depends On**: —
> **Pi-Session-File**: /home/agent/.pi/agent/sessions/-home-agent/2026-03-11T05-49-48-160Z_5b6afb3f-e5f9-4575-bd0c-4fdc63706d30.jsonl

---

## Context

Current live state:

- `mitto-paivi.service` successfully starts the MCP server on `127.0.0.1:5757`
- `mitto-web.service` and `mitto-web-testi.service` start their web UIs normally, but log `Failed to start MCP server ... bind: address already in use`
- `ss -ltnp` shows port `5757` owned by the `mitto-paivi.service` process

This produces persistent warning noise and makes it unclear whether the conflict is intended configuration or an accidental default.

## Questions To Resolve

1. Should there be exactly one global MCP HTTP listener across all Mitto instances?
2. If yes, which service should own it and how should the others disable it cleanly?
3. If no, does Mitto support per-instance MCP port configuration so each service can bind separately?
4. Are any existing clients depending specifically on `127.0.0.1:5757`?

## Suggested Steps

1. Inspect Mitto docs/config/env handling for MCP listener settings
2. Check user service drop-ins and wrapper scripts for existing MCP-related config
3. Choose and document the intended ownership model
4. Update service definitions and restart the affected units
5. Confirm clean journals after restart
