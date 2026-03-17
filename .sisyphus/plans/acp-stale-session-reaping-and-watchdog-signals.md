# ACP Stale Session Reaping and Watchdog Signals

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: Mitto accumulates long-lived `pykoclaw acp` supervisor processes that stay idle with no active Claude child, and the watchdog currently labels each one as a red crash concern. We need to distinguish stale/orphaned ACP sessions from real crashes, identify the root cause of how these stale idle ACP parents are born, and fix both lifecycle cleanup and watchdog classification.
>
> **Estimated Effort**: Short
> **Depends On**: —
> **Reported**: 2026-03-16 by akaihola
> **Session Pointer**: pending session_meta

---

## Context

### Problem

The ACP watchdog report is producing noisy red alerts like "No claude child process (may have crashed)" for many long-lived ACP parent processes. Investigation on 2026-03-16 showed these processes are usually:

- direct children of long-lived `mitto web` processes
- sleeping in `do_epoll_wait`
- at `0.0%` CPU for many hours or days
- often unmapped to an active session (`Session: ?`)
- frequently without any child process at all

This strongly suggests a stale/orphaned ACP lifecycle issue rather than 1:1 active Claude crashes.

One inspected ACP (`2581589`) also had a live child process even though the watchdog reported "No claude child process", which means the detector's current child-matching heuristic is too narrow and can false-positive on healthy sessions.

### Why it matters

1. **Operational noise**: Matrix reports overstate the severity and train us to ignore watchdog alerts.
2. **Possible resource leak**: stale ACP supervisors may accumulate indefinitely under Mitto.
3. **Poor diagnosability**: red alerts do not currently separate true crash/restart loops from idle leftovers.

### Current evidence

- Reported PIDs are mostly still alive long after the report.
- Their parent is a long-lived `mitto web` process.
- Their wait channel is `do_epoll_wait`, consistent with idle event-loop waiting.
- Some previously reported PIDs disappeared later, suggesting churn/cleanup lag rather than persistent stuck active sessions.
- The watchdog code currently flags red immediately when no direct child command contains the substring `claude`.
- At least one inspected ACP (`2581589`) had a live child process while still being reported as "No claude child process", proving the current heuristic can false-positive on healthy sessions.

### Session pointer

Pykoclaw-Session-File: 27c5bd92-6068-45b2-b1fd-b81349d96d0c
Pykoclaw-Session: acp-11f19467
Pykoclaw-Session-Slug: 2026-03-16T04:05:46.724438+00:00_11f19467

### Related

- `acp-crash-resilience.md`
- `acp-context-loss-on-mitto.md`
- `ACP_ISSUES_LOG.md`
- `my-knowledge/.claude/skills/investigate-stuck/diagnose.py`

---

## Investigation / Fix Plan

1. Inspect and identify the Mitto/ACP code paths that create ACP processes, attach workers, and retain them after request completion.
2. Find the root cause of how stale idle ACP parents are born: normal session end without teardown, failed worker spawn/attach, restart edge case, pooling-by-design, or session bookkeeping mismatch.
3. Determine whether idle ACP parents are expected pooled workers or unintended leftovers.
4. Broaden watchdog child/session detection so it does not depend solely on `claude` appearing in a direct child command line.
5. Reclassify watchdog output:
   - stale idle ACP with no active session -> warning/info
   - active session with missing worker / restart loop / timeout -> red concern
6. Add cleanup or reaping for truly stale ACP sessions if they are unintended leftovers.
7. Add regression coverage or at least a reproducible diagnostic script for the healthy-idle vs stale-orphan cases.

---

## TODOs

- [ ] 1. **Inspect pykoclaw codebase**: Locate Mitto/ACP integration code for process spawning, worker attachment, session completion, and cleanup
- [ ] 2. **Identify code paths**: Map the exact call chain from request arrival → ACP spawn → worker attach → request completion → retention/cleanup
- [ ] 3. **Root cause analysis**: Determine how stale idle ACP parents are born (failed spawn/attach, restart edge case, normal completion without teardown, pooling-by-design, bookkeeping mismatch)
- [ ] 4. **Design fix**: Based on root cause, design either lifecycle cleanup (if unintended) or pooling management (if intended)
- [ ] 5. **Fix watchdog heuristic**: Broaden child detection beyond `claude` substring; reclassify stale idle ACPs as warning/info
- [ ] 6. **Implement and test**: Apply fix, verify watchdog alerts are accurate, ensure no regression in active session handling
- [ ] 7. **Add regression test**: Reproducible diagnostic for healthy-idle vs stale-orphan cases
