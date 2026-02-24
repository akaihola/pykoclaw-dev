# ACP Sessions Losing Context on Mitto

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: ACP sessions on Mitto (Ditto) are losing context — the agent
> forgets prior conversation history. This may be related to service restarts or
> a bug in the session/load resume flow (implemented 2026-02-21). Needs
> investigation to determine whether the `session/load` implementation is
> working correctly end-to-end.
>
> **Estimated Effort**: Unknown (investigation first)
> **Depends On**: session-resume-across-restarts (Done)
> **Reported**: 2026-02-24 by akaihola

---

## Context

### Problem

Users report that ACP sessions on Mitto lose context — the agent no longer
remembers what was discussed earlier in the conversation. This was the exact
problem that `session/load` was designed to solve (see
`session-resume-across-restarts.md`, completed 2026-02-21).

### Possible Causes

1. **session/load not triggered**: Mitto may not be calling `session/load` on
   reconnect (capability not advertised? protocol mismatch?)
2. **DB lookup failure**: The conversation name derivation (`acp-{session_id[:8]}`)
   may not match what was stored
3. **Claude Code `--resume` failure**: The Claude Code session ID may be stale or
   expired, causing it to start fresh silently
4. **Service restart frequency**: If mitto-web restarts frequently (e.g., due to
   crashes or deploys), each restart cycle could break the resume chain
5. **Worker subprocess lifecycle**: Workers may not be passing resume_session_id
   correctly after the first prompt

### Related

- `session-resume-across-restarts.md` — the fix that was supposed to address this
- `ACP_ISSUES_LOG.md` — historical connection issues
- `pykoclaw-acp/backlog/003-session-load-resume.md` — session persistence design

---

## Investigation Plan

1. Check ACP file-based logs (`~/.local/state/pykoclaw/acp-*.log`) for
   `session/load` calls and their results
2. Check if `loadSession: true` appears in `initialize` response
3. Verify DB contains valid Claude Code session IDs for active conversations
4. Test manually: restart mitto-web, check if conversation resumes with context
5. Add diagnostic logging if `session/load` path is not being exercised

---

## TODOs

- [ ] 1. Investigate: check ACP logs for session/load activity after restart
- [ ] 2. Verify DB has valid session IDs for active conversations
- [ ] 3. Reproduce the context loss and identify root cause
- [ ] 4. Fix based on findings
- [ ] 5. Add regression test if applicable
