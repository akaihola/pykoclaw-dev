# Scheduled Task Delivery Visibility

## Status: Backlog
## Priority: 2

## TL;DR

> **Quick Summary**: Scheduled task results silently vanish when they target
> archived or idle-evicted conversations. Fix this on the pykoclaw side without
> requiring Mitto changes — through delivery queue monitoring, fallback routing,
> and stale delivery detection.
>
> **Estimated Effort**: Short
> **Depends On**: (none)

---

## Motivation

All three active scheduled tasks (Willison blog digest, ACP watchdog, nightly
dev review) deliver results back to their originating ACP conversation. If that
conversation is archived in Mitto (ACP process stopped) or idle-evicted from
the client pool (10-min timeout), deliveries stay `pending` in the SQLite
delivery queue indefinitely. Mitto has no unread badge — only a transient
5-second toast — so missed deliveries are invisible.

This is a pykoclaw delivery reliability problem, not a Mitto UI problem.

## Expected Outcome

- No scheduled task result is silently lost
- The user is informed when deliveries can't be routed
- Stale pending deliveries are detected and handled
- All fixes live in pykoclaw Python code (no Mitto Go/JS changes)

## What's Doable Without Mitto Changes

### Fix 1: Fallback `target_conversation` on scheduled tasks

**Effort: Quick (config change)**

Reconfigure existing tasks to set `target_conversation` to a known
always-active session (e.g., a dedicated "dashboard" conversation). This is a
pure DB update — no code changes.

Limitation: requires manually maintaining an active session. If that session
gets archived too, same problem.

### Fix 2: Stale delivery monitor (scheduled task)

**Effort: Quick**

A new scheduled task (or addition to the existing watchdog) that queries the
`delivery_queue` for items in `pending` status older than N minutes. If found,
it reports them in its own output — creating visibility into stuck deliveries.

```python
# Pseudocode
stale = db.execute("""
    SELECT * FROM delivery_queue
    WHERE status = 'pending'
    AND created_at < datetime('now', '-15 minutes')
""")
if stale:
    report(f"{len(stale)} stale deliveries found")
```

### Fix 3: Delivery retry with fallback routing (pykoclaw-acp)

**Effort: Short**

Enhance `_process_pending_deliveries()` in pykoclaw-acp's server.py:

1. Track how long each delivery has been `pending`
2. If a delivery is older than a threshold (e.g., 15 min) and its target
   conversation is not in the active pool, attempt re-routing to a configurable
   fallback conversation
3. If no fallback is available, mark as `failed` with a reason (not silently
   `pending` forever)

This keeps all changes in `pykoclaw-acp/src/pykoclaw_acp/server.py`.

### Fix 4: Delivery TTL and expiry

**Effort: Quick**

Add a TTL column (or use `created_at` + config) to the delivery queue. Pending
deliveries older than the TTL get marked `expired` instead of sitting forever.
Log a warning when this happens.

### Fix 5: Delivery queue summary in nightly review

**Effort: Quick**

The existing nightly dev review script (`~/.local/bin/nightly-dev-review.py`)
could include a delivery queue health check — count of pending items, oldest
pending age, any failed/expired items.

## Recommended Implementation Order

1. **Fix 3** (fallback routing) — now the clear priority: addresses both the
   original archived-conversation problem and the new WorkerPool name mismatch.
   Pure asyncio code, clean to implement.
2. **Fix 4** (TTL + expiry) — prevents unbounded accumulation, cheapest
3. **Fix 2** (stale monitor in watchdog) — immediate visibility
4. **Fix 1** (reconfigure tasks) — interim workaround
5. **Fix 5** (nightly review integration) — nice-to-have

## Impact of Process Isolation Refactoring (2026-02-21)

The WorkerPool refactoring (replacing ClientPool with subprocess-isolated
workers) affects this plan in three ways:

### What improved

The ACP server is now **pure asyncio** — no SDK/anyio code in the same process.
The delivery polling loop (`_process_pending_deliveries()`) is more reliable
because anyio cancel scope leaks can no longer interfere with it. Fix 3
(fallback routing) is cleaner to implement since it's straightforward asyncio
code, not entangled with SDK interactions.

### What didn't change

The core problem is unchanged: if the target conversation isn't active,
deliveries sit in `pending` forever. Fixes 1, 2, 4, 5 are all unaffected —
they're config changes, DB operations, or separate scripts.

### New issue: conversation name mismatch

WorkerPool generates conversation names as `acp-{session_id[:8]}` (e.g.
`acp-a1b2c3d4`), while scheduled tasks reference whatever name was set at
creation time (e.g. `acp-source`). The delivery matcher in
`_process_pending_deliveries()` does a string comparison between these — so even
if the target conversation *is* active, the names won't match. This was less of
an issue with the old ClientPool where naming was more stable.

**This makes Fix 3 the clear first priority** — it addresses both the original
problem (archived conversations) and the new name mismatch problem. Fallback
routing with age-tracking catches both failure modes.

## Implementation Notes

Key code locations:
- Delivery queue: `pykoclaw/src/pykoclaw/db.py` (`enqueue_delivery`,
  `get_pending_deliveries`, `mark_delivered`)
- ACP delivery polling: `pykoclaw-acp/src/pykoclaw_acp/server.py`
  (`_process_pending_deliveries`, lines 253–296)
- Worker naming: `pykoclaw-acp/src/pykoclaw_acp/worker_pool.py`
  (`conversation_name = f"acp-{session_id[:8]}"`, line 179)
- Scheduler: `pykoclaw/src/pykoclaw/scheduler.py` (`run_task`)
- Watchdog task: existing scheduled task `be096e52`

## Requires Mitto Changes (Deferred)

These fixes would improve the situation further but need Go/JS changes in Mitto:

### Unread badge / persistent notification

Mitto currently uses only a transient 5-second toast for new messages. An unread
badge on archived conversations would make missed deliveries visible without
requiring the user to actively check. Requires Mitto frontend + backend changes.

### Auto-unarchive on delivery

When a delivery arrives for an archived conversation, Mitto could automatically
unarchive it (restart the ACP process) so the delivery can be picked up. Requires
Mitto to expose an API for restarting sessions programmatically.

## Feasibility Summary

| Fix | Mitto Changes Needed? | Effort |
|-----|-----------------------|--------|
| Fix 1: Fallback target_conversation | No — pure DB update | Quick |
| Fix 2: Stale delivery monitor | No — Python scheduled task | Quick |
| Fix 3: Retry with fallback routing | No — pykoclaw-acp Python | Short |
| Fix 4: Delivery TTL + expiry | No — pykoclaw Python | Quick |
| Fix 5: Nightly review integration | No — Python script update | Quick |
| Unread badge | **Yes** — Mitto Go + JS | Medium |
| Auto-unarchive on delivery | **Yes** — Mitto Go API | Medium |

## Related

- [scheduled-task-delivery.md] — Original delivery queue implementation (Done)

[scheduled-task-delivery.md]: scheduled-task-delivery.md
