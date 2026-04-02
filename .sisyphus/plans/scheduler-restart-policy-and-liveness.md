# Scheduler Restart Policy & Liveness Monitoring

## Status: Backlog

## Priority: 1

## TL;DR

> **Quick Summary**: Tyko's scheduler service (and pipsa's and zennie's) died
> on 2026-03-24 after a NixOS rebuild sent SIGTERM. They never restarted
> because their systemd units use `Restart=on-failure`, which treats a
> managed SIGTERM as a clean stop. Result: 7 scheduled tasks (ACP health
> checks, daily AI scans, Agent Commons reports, etc.) have been stuck for
> 4+ days with no deliveries to Matrix.
>
> This plan fixes three things:
>
> 1. **Immediate ops**: restart the dead schedulers now.
> 2. **NixOS config**: change all `pykoclaw-scheduler-*` services from
>    `Restart=on-failure` to `Restart=always` (matching the channel listeners).
> 3. **App-level monitoring**: add a `get_overdue_tasks()` function to
>    `pykoclaw/db.py` so dead-scheduler scenarios are detectable
>    programmatically, with full TDD test coverage.
> 4. **Documentation**: record the failure mode in CLAUDE.md and a new
>    `.memory/` file so the "SIGTERM + on-failure = dead" pattern is
>    permanently remembered.
>
> **Estimated Effort**: 1–2 hours
> **Depends On**: nothing
> **Parallel Execution**: NO — single-threaded, affects production services

---

## Root Cause Analysis

### What happened

On 2026-03-24 at 23:02:40 EET, all four production scheduler services
received SIGTERM simultaneously. Likely cause: a `home-manager switch` or
`nixos-rebuild` that replaced service unit files.

### Why they didn't restart

Scheduler services use `Restart=on-failure`. When systemd itself stops a
service (sending SIGTERM as part of a managed lifecycle event), it records
`Result=success` with `ExecMainStatus=15` (signal 15 = SIGTERM). Because
the result is "success", `Restart=on-failure` does not trigger.

Channel listener services (Matrix, WhatsApp, Slack) use `Restart=always`
and survived the same rebuild event.

### Evidence

```
$ systemctl --user show pykoclaw-scheduler-tyko -p Result -p ExecMainStatus
Result=success
ExecMainStatus=15

$ systemctl --user show pykoclaw-scheduler-pipsa -p Result -p ExecMainStatus
Result=success
ExecMainStatus=15

$ systemctl --user show pykoclaw-scheduler-zennie -p Result -p ExecMainStatus
Result=success
ExecMainStatus=15
```

All three stopped at the same instant. The coleaders scheduler was later
manually restarted. The testi scheduler has its own separate issue (broken
venv: `ModuleNotFoundError: No module named 'platformdirs'`).

### Timeline

| Time (EET)          | Event                                                   |
| ------------------- | ------------------------------------------------------- |
| 2026-03-24 15:34:19 | Last scheduler restart (deploy)                         |
| 2026-03-24 18:00:50 | Last scheduled delivery (ACP health check → Matrix DM)  |
| 2026-03-24 23:02:40 | All schedulers stopped (SIGTERM, rebuild)               |
| 2026-03-24 23:02:40 | Result=success, ExecMainStatus=15 → no auto-restart     |
| 2026-03-25 – 03-28  | Schedulers dead. 7 tasks overdue. No Matrix deliveries. |

### NixOS config file

Service definitions live in:
`~/repos/nixos-config/home-manager/home-agent-gogo.nix`

Lines with `Restart = "on-failure"` that need changing to `"always"`:

- Line 250: `pykoclaw-scheduler-pipsa`
- Line 278: `pykoclaw-scheduler-tyko`
- Line 305: `pykoclaw-scheduler-zennie`
- Line 332: `pykoclaw-scheduler-coleaders`
- Line 451: `pykoclaw-scheduler-testi`

Channel listeners already use `Restart = "always"` (lines 360, 389, 419, 479).

### Secondary observations (not in scope but noted)

1. **Transient `next_batch` validation errors** – matrix-nio periodically
   gets sync responses missing `next_batch` (matrix.org server-side).
   Non-fatal; sync loop retries and recovers. No code fix needed.
2. **Testi venv broken** – `ModuleNotFoundError: No module named
'platformdirs'` crash-looping since 2026-03-24. Separate issue.

---

## Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:test-driven-development
> and superpowers:verification-before-completion. Steps use checkbox (`- [ ]`)
> syntax for tracking.

**Goal:** Ensure pykoclaw scheduler services survive NixOS rebuilds and
provide app-level detection of overdue tasks.

**Architecture:** Production `get_overdue_tasks()` function in `pykoclaw/db.py`;
NixOS service unit changes in `~/repos/nixos-config`; memory + CLAUDE.md docs.

**Tech Stack:** Python 3.12+, SQLite, systemd, NixOS/home-manager

---

### Task 0: Immediate Ops — Restart Dead Schedulers

No code changes. Pure operational recovery.

- [ ] **Step 1: Restart the three dead scheduler services**

```bash
systemctl --user start pykoclaw-scheduler-tyko
systemctl --user start pykoclaw-scheduler-pipsa
systemctl --user start pykoclaw-scheduler-zennie
```

- [ ] **Step 2: Verify they're running**

```bash
systemctl --user is-active pykoclaw-scheduler-tyko
systemctl --user is-active pykoclaw-scheduler-pipsa
systemctl --user is-active pykoclaw-scheduler-zennie
```

Expected: all three report `active`.

- [ ] **Step 3: Verify scheduled tasks resume**

Wait ~60s for the scheduler poll loop, then check:

```bash
sqlite3 ~/my-knowledge/pykoclaw.db \
  "SELECT id, next_run FROM scheduled_tasks WHERE status='active' ORDER BY next_run LIMIT 5;"
```

Expected: `next_run` values should now be in the future (scheduler
recalculated them on startup).

---

### Task 1: Create Feature Worktree

- [ ] **Step 1: Create the worktree**

```bash
cd ~/prg/pykoclaw-dev
bin/create-worktree.sh scheduler-liveness
```

- [ ] **Step 2: Verify worktree is ready**

```bash
cd ~/prg/pykoclaw-worktrees/scheduler-liveness
uv run pytest pykoclaw/tests/ -x -q
```

Expected: existing tests pass.

---

### Task 2: TDD — `get_overdue_tasks()` in `pykoclaw/db.py`

**Files:**

- Modify: `pykoclaw/src/pykoclaw/db.py` (add function)
- Create: `pykoclaw/tests/test_scheduler_liveness.py` (tests)

#### RED phase

- [ ] **Step 1: Write failing tests**

Create `pykoclaw/tests/test_scheduler_liveness.py` with tests for
`get_overdue_tasks()`:

- `test_no_tasks_returns_empty`
- `test_future_task_not_overdue`
- `test_recent_task_within_grace_not_overdue` (30 min old, 1h grace)
- `test_stale_task_detected` (2h old, 1h grace)
- `test_inactive_task_ignored` (paused/completed)
- `test_null_next_run_ignored`
- `test_multiple_overdue_sorted_by_next_run`
- `test_custom_grace_period`
- `test_real_world_scenario_dead_scheduler` (5 tasks, 3+ days overdue)

Import `get_overdue_tasks` from `pykoclaw.db`.

- [ ] **Step 2: Run tests – verify they FAIL**

```bash
cd ~/prg/pykoclaw-worktrees/scheduler-liveness
PYKOCLAW_DATA=/tmp/pykoclaw-test-liveness uv run pytest pykoclaw/tests/test_scheduler_liveness.py -v
```

Expected: `ImportError` – `get_overdue_tasks` doesn't exist yet.

#### GREEN phase

- [ ] **Step 3: Implement `get_overdue_tasks()` in `pykoclaw/db.py`**

```python
def get_overdue_tasks(
    db: DbConnection,
    *,
    grace_period: timedelta = timedelta(hours=1),
) -> list[dict]:
    """Find active scheduled tasks whose next_run is overdue.

    A task is overdue when ``next_run`` is more than *grace_period* in the
    past.  Detects dead-scheduler scenarios.
    """
    cutoff = (datetime.now(timezone.utc) - grace_period).isoformat()
    rows = db.execute(
        "SELECT id, conversation, next_run FROM scheduled_tasks "
        "WHERE status = 'active' AND next_run IS NOT NULL AND next_run < ? "
        "ORDER BY next_run",
        (cutoff,),
    ).fetchall()
    return [dict(r) for r in rows]
```

- [ ] **Step 4: Run tests – verify they PASS**

```bash
PYKOCLAW_DATA=/tmp/pykoclaw-test-liveness uv run pytest pykoclaw/tests/test_scheduler_liveness.py -v
```

Expected: all 9 tests pass.

- [ ] **Step 5: Run full test suite**

```bash
PYKOCLAW_DATA=/tmp/pykoclaw-test-liveness uv run pytest pykoclaw/tests/ -x -q
```

Expected: no regressions.

- [ ] **Step 6: Commit**

```bash
git add pykoclaw/src/pykoclaw/db.py pykoclaw/tests/test_scheduler_liveness.py
git commit -m "feat(db): add get_overdue_tasks() for scheduler liveness detection

Detects active scheduled tasks whose next_run is in the past beyond a
configurable grace period. This would have caught the dead-scheduler
scenario of 2026-03-24 where SIGTERM + Restart=on-failure left schedulers
stopped for 4+ days.

Pi-Session: 00728277"
```

---

### Task 3: NixOS Config — Change Restart Policy

**Files:**

- Modify: `~/repos/nixos-config/home-manager/home-agent-gogo.nix`

- [ ] **Step 1: Change all scheduler `Restart` values**

In `~/repos/nixos-config/home-manager/home-agent-gogo.nix`, change every
`pykoclaw-scheduler-*` service's `Restart = "on-failure"` to
`Restart = "always"`. There are 5 occurrences (pipsa, tyko, zennie,
coleaders, testi).

- [ ] **Step 2: Commit**

```bash
cd ~/repos/nixos-config
git add home-manager/home-agent-gogo.nix
git commit -m "fix(systemd): scheduler services Restart=always (not on-failure)

on-failure does not restart after SIGTERM from nixos-rebuild, because
systemd records it as Result=success (ExecMainStatus=15). This left all
scheduler services dead after the 2026-03-24 rebuild. Channel listeners
already used Restart=always and survived.

Pi-Session: 00728277"
```

- [ ] **Step 3: Rebuild NixOS**

```bash
sudo -u akaihola /home/akaihola/repos/nixos-config/pull-rebase-rebuild.sh
```

- [ ] **Step 4: Verify new service files have `Restart=always`**

```bash
systemctl --user cat pykoclaw-scheduler-tyko.service | grep Restart
```

Expected: `Restart=always`

- [ ] **Step 5: Verify all schedulers still active after rebuild**

```bash
for svc in tyko pipsa zennie coleaders; do
  echo "$svc: $(systemctl --user is-active pykoclaw-scheduler-$svc)"
done
```

Expected: all `active`.

---

### Task 4: Documentation Updates

**Files:**

- Modify: `~/prg/pykoclaw-dev/CLAUDE.md`
- Create: `~/prg/pykoclaw-dev/.memory/scheduler-restart-policy.md`
- Modify: `~/prg/pykoclaw-dev/.memory/INDEX.md` (if project-root level exists)

- [ ] **Step 1: Create memory file**

Create `.memory/scheduler-restart-policy.md`:

```markdown
# Scheduler Restart Policy — SIGTERM Survival

**Tags:** systemd, scheduler, nixos, reliability
**Related:** [nixos-systemd.md]

## The failure

NixOS rebuilds send SIGTERM to user services when replacing unit files.
`Restart=on-failure` treats SIGTERM as a clean stop (Result=success,
ExecMainStatus=15) and does **not** restart. Result: all scheduler services
died on 2026-03-24 and stayed dead for 4+ days.

## The fix

All `pykoclaw-scheduler-*` services now use `Restart=always` in the NixOS
home-manager config, matching channel listeners (Matrix, WhatsApp, Slack).

## Detection

`pykoclaw.db.get_overdue_tasks()` detects active tasks with `next_run` in
the past beyond a grace period. Use for health checks / alerting.

[nixos-systemd.md]: ~/.config/coding-agents/nixos-systemd.md
```

- [ ] **Step 2: Add gotcha to CLAUDE.md**

Add to the "Important gotchas" section:

```markdown
- **Scheduler services must use `Restart=always`** — `Restart=on-failure`
  does NOT restart after SIGTERM from NixOS rebuild (systemd records
  Result=success, ExecMainStatus=15). All `pykoclaw-scheduler-*` services
  were dead for 4+ days after the 2026-03-24 rebuild. Channel listeners
  (Matrix, WhatsApp, Slack) survived because they already used
  `Restart=always`. See [scheduler-restart-policy.md] memory note.
```

- [ ] **Step 3: Commit docs**

```bash
git add CLAUDE.md .memory/scheduler-restart-policy.md
git commit -m "docs: record scheduler SIGTERM restart policy failure mode

Pi-Session: 00728277"
```

---

### Task 5: Merge, Deploy, and Verify

- [ ] **Step 1: Run full QA check**

```bash
cd ~/prg/pykoclaw-dev
bin/qa-check.sh scheduler-liveness
```

- [ ] **Step 2: Merge feature branch**

```bash
bin/merge-feature.sh scheduler-liveness
```

- [ ] **Step 3: Deploy**

```bash
./install-dev.sh
```

- [ ] **Step 4: Verify production overdue-task count is zero**

```bash
cd ~/prg/pykoclaw-dev
uv run python3 -c "
from pykoclaw.db import init_db, get_overdue_tasks
from pathlib import Path
from datetime import timedelta
db = init_db(Path.home() / 'my-knowledge' / 'pykoclaw.db')
overdue = get_overdue_tasks(db, grace_period=timedelta(hours=1))
print(f'Overdue tasks: {len(overdue)}')
for t in overdue: print(f'  {t[\"id\"]}  next_run={t[\"next_run\"]}')
assert len(overdue) == 0, f'Still {len(overdue)} overdue tasks!'
print('All clear.')
"
```

Expected: `Overdue tasks: 0` / `All clear.`

- [ ] **Step 5: Cleanup worktree**

```bash
bin/cleanup-worktree.sh scheduler-liveness
```

---

### Task 6: Full Failure Analysis Document

- [ ] **Step 1: Update the plan file status to Done**

Update this file's `## Status:` to `Done` and add `## Completed:` date.

- [ ] **Step 2: Verify understanding is documented**

Ensure the following are all recorded (in CLAUDE.md, .memory, or this plan):

1. **Proximate cause**: SIGTERM from nixos-rebuild killed scheduler processes.
2. **Why no restart**: `Restart=on-failure` + systemd's own SIGTERM = Result=success.
3. **Why Matrix listener survived**: it already had `Restart=always`.
4. **Why it went undetected for 4 days**: no monitoring for overdue tasks.
5. **Testi crash-loop**: separate `platformdirs` import error in broken venv.
6. **Transient matrix-nio `next_batch` errors**: matrix.org server hiccups,
   non-fatal, auto-recovers.
