# Code Review Fixes — All 18 Items

## Status: Done

## TL;DR

> **Quick Summary**: Implement all 18 fixes from Oracle's code review across the three pykoclaw subpackages (core, chat, whatsapp), ordered safest-first. Each commit is gated by the full test suite.
>
> **Deliverables**: 18 code fixes across ~15 files, organized into 13 atomic commits
> - 4 critical bug fixes (dead code, broken async, race conditions, silent misrouting)
> - 6 important improvements (error handling, type safety, consistency)
> - 5 minor cleanups (readability, precision)
> - 3 nits (naming, dead surface, noting)
>
> **Estimated Effort**: Medium (3–4 hours)
> **Parallel Execution**: NO — sequential commits, each gated by tests
> **Critical Path**: Fix #0 (test baseline) → Fix #1 (dead code) → Fixes #3/#8/#9 (queue.py) → Fix #16 (rename blast radius)

---

## Context

### Original Request
Implement all 18 fixes identified by Oracle's code review of the pykoclaw monorepo, committing frequently.

### Interview Summary
**Key Discussions**:
- Oracle performed a thorough review covering simplicity, brevity, clarity, maintainability
- User wants ALL 18 addressed, not a subset
- Commit-per-logical-group, not commit-per-fix

**Research Findings (Metis)**:
- Baseline: 30 tests pass (core), 80 tests pass (whatsapp), chat tests broken pre-existing (ModuleNotFoundError)
- `agent.py` has zero imports anywhere — truly dead
- Fix #16 (`id` → `task_id`) touches db.py + callers in tools.py, scheduler.py
- Fix #6 (data dirs) is a config default change — breaking for existing `~/.pykoclaw/` users
- Fix #2 (auth.py) is hard to test — Go-backed blocking call

### Metis Review
**Identified Gaps** (addressed):
- Chat test breakage needs handling → resolved: exclude from gate, note-only
- Fix #4 ambiguity (docstring vs code) → resolved: handle "once" explicitly, return None for unknown
- Fix #6 backward compat → resolved: change defaults only, no migration
- Fix #17 remove vs wire-up → resolved: remove dead methods
- Fix #18 code vs note → resolved: no code change, skip

---

## Work Objectives

### Core Objective
Address all 18 code review findings to improve correctness, thread-safety, type accuracy, and maintainability across the pykoclaw monorepo.

### Concrete Deliverables
- 13 atomic commits, each passing `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/`
- 1 dead file deleted (`agent.py`)
- Thread-safe `OutgoingQueue` with `deque`
- Fixed auth flow, scheduler error handling, scheduling dispatch
- Consistent type hints, naming, imports across all 3 subpackages

### Definition of Done
- [x] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass (≥110 tests, 0 failures)
- [x] All 18 review items addressed in git history
- [x] No regressions in existing behavior

### Must Have
- Every commit passes the test suite
- Behavioral fixes for critical bugs (#2, #3, #5)
- Type hint consistency (#7)
- Dead code removal (#1)

### Must NOT Have (Guardrails)
- **MUST NOT** change SQLite schema in any fix
- **MUST NOT** rename `ScheduledTask.id` model field (only function parameters in fix #16)
- **MUST NOT** add new pip dependencies (all fixes use stdlib)
- **MUST NOT** refactor code adjacent to fix targets — surgical changes only
- **MUST NOT** add DB migration logic for fix #6 (just change defaults)
- **MUST NOT** wire up lifecycle hooks in fix #17 (just remove dead surface)
- **MUST NOT** change behavior except where explicitly fixing bugs (#2, #3, #5)

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks verified by running commands. No human action permitted.

### Test Decision
- **Infrastructure exists**: YES (pytest, both subpackages)
- **Automated tests**: YES (tests-after — add targeted tests for fixes #5, #10)
- **Framework**: pytest
- **Gate command**: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`
- **Note**: `pykoclaw-chat` tests excluded — broken pre-existing (ModuleNotFoundError). Chat plugin has only 4 trivial tests; the fix is a workspace config issue, not related to these code changes.

---

## Execution Strategy

### Sequential Commits (safest → highest blast radius)

```
Commit 1: Fix #1 — Delete dead agent.py (+ resolves #11)
Commit 2: Fixes #3, #8, #9 — queue.py thread-safety + deque + orphan field
Commit 3: Fix #2 — auth.py broken async/blocking mix
Commit 4: Fix #5 — scheduler error handling for recurring tasks
Commit 5: Fix #4 — scheduling.py explicit "once" + None for unknown
Commit 6: Fix #10 — handler.py regex cache keyed on trigger_name
Commit 7: Fixes #12, #15 — handler.py chr(10) + connection.py dedent alias
Commit 8: Fix #13 — agent_core.py AsyncGenerator return type
Commit 9: Fix #14 — whatsapp __init__.py consistent imports
Commit 10: Fix #6 — whatsapp config.py data directory alignment
Commit 11: Fix #7 — type hints: sqlite3.Connection → DbConnection
Commit 12: Fix #16 — id → task_id parameter rename in db.py + callers
Commit 13: Fix #17 — remove dead protocol methods
```

No parallel execution — each commit must be verified before proceeding.

---

## TODOs

- [x] 0. Capture baseline test state

  **What to do**:
  - Run `uv run pytest pykoclaw/tests/ --tb=short -q` and record pass count (expect 30)
  - Run `uv run pytest pykoclaw-whatsapp/tests/ --tb=short -q` and record pass count (expect 80)
  - This establishes the pre-change baseline. If tests are already failing, stop and report.

  **Must NOT do**:
  - Do not fix any pre-existing test failures
  - Do not modify any code

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single verification step, no code changes
  - **Skills**: [`git-master`]
    - `git-master`: Will need git for subsequent commits

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (must be first)
  - **Blocks**: All subsequent tasks
  - **Blocked By**: None

  **References**:
  - `pykoclaw/tests/` — 5 test files (test_db.py, test_tools.py, test_agent_core.py, test_plugins.py, test_config.py)
  - `pykoclaw-whatsapp/tests/` — 6 test files (test_handler.py, test_connection.py, test_queue.py, test_batch.py, test_whatsapp_plugin.py, test_config.py)

  **Acceptance Criteria**:
  - [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass
  - [ ] `uv run pytest pykoclaw-whatsapp/tests/ --tb=short -q` → all pass
  - [ ] Baseline counts recorded for comparison

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Verify core tests pass
    Tool: Bash
    Preconditions: Workspace installed with uv
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ --tb=short -q
      2. Assert: exit code 0
      3. Assert: output contains "passed"
    Expected Result: 30 tests passed, 0 failed
    Evidence: Terminal output captured

  Scenario: Verify whatsapp tests pass
    Tool: Bash
    Preconditions: Workspace installed with uv
    Steps:
      1. Run: uv run pytest pykoclaw-whatsapp/tests/ --tb=short -q
      2. Assert: exit code 0
      3. Assert: output contains "passed"
    Expected Result: 80 tests passed, 0 failed
    Evidence: Terminal output captured
  ```

  **Commit**: NO

---

- [x] 1. Delete dead `agent.py` (Review items #1, #11)

  **What to do**:
  - Delete `pykoclaw/src/pykoclaw/agent.py`
  - Verify no imports reference it: `grep -r "from pykoclaw.agent import\|from pykoclaw import agent\|import pykoclaw.agent" pykoclaw/`
  - This automatically resolves #11 (duplicated readline helpers) since the duplicate was in agent.py

  **Must NOT do**:
  - Do not modify `agent_core.py` or any other file — only delete agent.py
  - Do not remove the `agent_core` module

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file deletion, trivial verification
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit after deletion

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None directly
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw/src/pykoclaw/agent.py` — The file to delete (98 lines, fully superseded by agent_core.py)
  - `pykoclaw/src/pykoclaw/agent_core.py` — The replacement that already exists and is used by chat plugin + scheduler

  **Acceptance Criteria**:
  - [ ] `pykoclaw/src/pykoclaw/agent.py` does not exist
  - [ ] `uv run python -c "from pykoclaw.agent_core import query_agent; print('OK')"` → "OK"
  - [ ] `grep -r "pykoclaw.agent" pykoclaw/src/ --include="*.py" | grep -v agent_core | grep -v __pycache__` → empty
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: agent.py is deleted and nothing breaks
    Tool: Bash
    Preconditions: Baseline tests passing
    Steps:
      1. Run: rm pykoclaw/src/pykoclaw/agent.py
      2. Run: grep -r "pykoclaw\.agent" pykoclaw/src/ --include="*.py" | grep -v agent_core | grep -v __pycache__
      3. Assert: no output (no remaining references)
      4. Run: uv run python -c "from pykoclaw.agent_core import query_agent; print('OK')"
      5. Assert: prints "OK"
      6. Run: uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q
      7. Assert: exit code 0, all tests pass
    Expected Result: Clean deletion, no references, tests pass
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix: delete dead agent.py superseded by agent_core.py`
  - Files: `pykoclaw/src/pykoclaw/agent.py` (deleted)
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 2. Fix queue.py: thread-safety, deque, orphan field (Review items #3, #8, #9)

  **What to do**:
  - **#9**: Remove orphan class-level `_queue: list[QueuedMessage] = field(default_factory=list)` at line 35. Remove `field` from the `dataclass` import (keep `dataclass` for `QueuedMessage`).
  - **#8**: Change `self._queue` from `list` to `collections.deque` in `__init__`. Change `self._queue.pop(0)` to `self._queue.popleft()` in `flush()`. Change `self._queue.append(...)` stays the same (deque supports append).
  - **#3**: Add `import threading` at top. Add `self._lock = threading.Lock()` in `__init__`. Wrap the bodies of `enqueue()`, `send()`, and `flush()` in `with self._lock:`. Remove `self._flushing` flag (the lock replaces it). Update docstring to accurately describe the locking.
  - Update type annotation: `_queue` should be `deque[QueuedMessage]`.

  **Must NOT do**:
  - Do not change OutgoingQueue's public API (method signatures)
  - Do not add asyncio locks (use threading.Lock — matches ThreadSafeConnection pattern)
  - Do not refactor flush() logic beyond the specific fixes
  - Do not change QueuedMessage dataclass

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file, well-scoped changes
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/queue.py` — The file to modify (96 lines)
  - `pykoclaw/src/pykoclaw/db.py:13-57` — `ThreadSafeConnection` — Pattern to follow for lock wrapping
  - `pykoclaw-whatsapp/tests/test_queue.py` — Existing tests (will verify no regression)

  **Acceptance Criteria**:
  - [ ] `queue.py` has `import threading` and `from collections import deque`
  - [ ] `OutgoingQueue.__init__` creates `self._queue = deque()` and `self._lock = threading.Lock()`
  - [ ] No `self._flushing` flag exists
  - [ ] No class-level `_queue: list[...] = field(...)` line exists
  - [ ] `flush()` uses `self._queue.popleft()` not `self._queue.pop(0)`
  - [ ] `enqueue()`, `send()`, `flush()` bodies wrapped in `with self._lock:`
  - [ ] `field` is not imported (or at least not used on OutgoingQueue)
  - [ ] `uv run pytest pykoclaw-whatsapp/tests/test_queue.py --tb=short -q` → all pass
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Queue uses deque and has lock
    Tool: Bash
    Preconditions: queue.py modified
    Steps:
      1. Run: uv run python -c "from pykoclaw_whatsapp.queue import OutgoingQueue; q = OutgoingQueue(); print(type(q._queue).__name__, hasattr(q, '_lock'))"
      2. Assert: output is "deque True"
      3. Run: uv run python -c "from pykoclaw_whatsapp.queue import OutgoingQueue; q = OutgoingQueue(); assert not hasattr(q, '_flushing'); print('OK')"
      4. Assert: prints "OK"
    Expected Result: deque and lock present, _flushing removed
    Evidence: Terminal output captured

  Scenario: All queue tests still pass
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw-whatsapp/tests/test_queue.py -v --tb=short
      2. Assert: exit code 0, all 11 tests pass
    Expected Result: No regressions
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix(whatsapp): add thread-safety to OutgoingQueue, use deque, remove orphan field`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/queue.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 3. Fix auth.py broken async/blocking mix (Review item #2)

  **What to do**:
  - Replace the broken `asyncio.create_task(shutdown_client(client))` pattern
  - Use a `threading.Event` approach: run `client.connect()` on a daemon thread, wait for the connected event on the main thread, then disconnect
  - The pattern:
    ```python
    connected = threading.Event()

    @client.event(ConnectedEv)
    def on_connected(_client, event):
        click.echo("✓ Successfully authenticated!")
        click.echo(f"  Credentials saved to {config.auth_dir}/")
        connected.set()

    thread = threading.Thread(target=client.connect, daemon=True)
    thread.start()
    if not connected.wait(timeout=120):
        click.echo("\n✗ Authentication timed out.")
        raise SystemExit(1)
    time.sleep(1)  # Let credentials flush
    client.disconnect()
    ```
  - Remove `async def run_auth()` → make it a plain `def run_auth()` since no async is needed
  - Remove `import asyncio` (no longer needed)
  - Add `import threading, time`
  - Update the caller in `__init__.py` to call `run_auth()` directly instead of `asyncio.run(run_auth())`

  **Must NOT do**:
  - Do not change the QR code display logic
  - Do not change the Neonize client setup
  - Do not add complex async patterns — keep it simple with threading.Event

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Two small files, clear pattern to follow
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/auth.py` — The file to fix (60 lines)
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py:32` — Caller: `asyncio.run(run_auth())` must change to `run_auth()`
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:86-104` — Reference: how the connection module uses threading + asyncio together (daemon thread pattern)

  **Acceptance Criteria**:
  - [ ] `auth.py` has no `import asyncio` and no `asyncio.create_task`
  - [ ] `auth.py` uses `threading.Event` for signaling connected state
  - [ ] `run_auth()` is a plain function (not `async def`)
  - [ ] `__init__.py` calls `run_auth()` directly (no `asyncio.run`)
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: auth.py has no broken async patterns
    Tool: Bash
    Preconditions: auth.py modified
    Steps:
      1. Run: grep -c "asyncio.create_task\|async def run_auth" pykoclaw-whatsapp/src/pykoclaw_whatsapp/auth.py
      2. Assert: output is "0"
      3. Run: grep -c "threading.Event\|connected.set()\|connected.wait" pykoclaw-whatsapp/src/pykoclaw_whatsapp/auth.py
      4. Assert: output ≥ 3
      5. Run: grep "asyncio.run(run_auth" pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py
      6. Assert: no output (caller updated)
    Expected Result: Async patterns replaced with threading.Event
    Evidence: Terminal output captured

  Scenario: No import or syntax errors
    Tool: Bash
    Steps:
      1. Run: uv run python -c "from pykoclaw_whatsapp.auth import run_auth; print(type(run_auth))"
      2. Assert: output is "<class 'function'>" (not coroutine function)
    Expected Result: run_auth is a regular function
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix(whatsapp): replace broken async auth with threading.Event pattern`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/auth.py`, `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 4. Fix scheduler error handling for recurring tasks (Review item #5)

  **What to do**:
  - In `scheduler.py`, move the `next_run` computation so recurring tasks (cron/interval) get their next run even on error
  - In the `except` block, compute `next_run` for cron/interval tasks instead of setting it to `None`
  - Only set `next_run = None` for `"once"` tasks on error
  - Add a test in `pykoclaw/tests/` that verifies a cron task gets next_run even when the agent call raises

  **Must NOT do**:
  - Do not change the scheduler loop structure
  - Do not add retry logic or backoff
  - Do not change how `update_task_after_run` works

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small change in scheduler.py + one new test
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw/src/pykoclaw/scheduler.py:29-64` — The `run_task` function with the broken except block
  - `pykoclaw/src/pykoclaw/scheduling.py:6-20` — `compute_next_run()` — used to compute next time
  - `pykoclaw/src/pykoclaw/db.py:227-239` — `update_task_after_run()` — sets status='completed' when next_run is None
  - `pykoclaw/tests/test_db.py` — Pattern for test fixtures

  **Acceptance Criteria**:
  - [ ] In `scheduler.py` except block: cron/interval tasks compute `next_run` via `compute_next_run()`
  - [ ] In `scheduler.py` except block: "once" tasks still set `next_run = None`
  - [ ] New test exists verifying recurring task survives an error
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Cron task computes next_run even on error
    Tool: Bash
    Steps:
      1. Run: grep -A5 "except Exception" pykoclaw/src/pykoclaw/scheduler.py
      2. Assert: output contains "compute_next_run" inside the except block
      3. Assert: output does NOT unconditionally set next_run = None
    Expected Result: Error handler preserves recurring scheduling
    Evidence: Terminal output captured

  Scenario: New test validates recurring task survival
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ -k "error" -v --tb=short
      2. Assert: at least 1 test related to error handling passes
    Expected Result: Test proves cron tasks survive errors
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix: preserve next_run for recurring tasks on error`
  - Files: `pykoclaw/src/pykoclaw/scheduler.py`, `pykoclaw/tests/test_scheduler.py` (new)
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 5. Fix scheduling.py: explicit "once" + None for unknown (Review item #4)

  **What to do**:
  - Change the `else` branch in `compute_next_run()` to handle `"once"` explicitly
  - Add a final `return None` for truly unknown schedule types
  - Update the docstring to match the new behavior
  - The function becomes:
    ```python
    if schedule_type == "cron":
        return croniter(schedule_value, base).get_next(datetime).isoformat()
    if schedule_type == "interval":
        return (base + timedelta(milliseconds=int(schedule_value))).isoformat()
    if schedule_type == "once":
        return schedule_value
    return None
    ```

  **Must NOT do**:
  - Do not add validation or raise ValueError for unknown types
  - Do not change the function signature

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 3-line change in one function
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw/src/pykoclaw/scheduling.py:6-20` — The function to fix
  - `pykoclaw/src/pykoclaw/tools.py:35` — Caller: `compute_next_run(schedule_type, schedule_value)` — must handle None return for unknown types (already does, since callers pass valid types)

  **Acceptance Criteria**:
  - [ ] `scheduling.py` has explicit `if schedule_type == "once": return schedule_value`
  - [ ] `scheduling.py` ends with `return None` for unknown types
  - [ ] Docstring accurately describes all three branches + None fallback
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Unknown schedule type returns None
    Tool: Bash
    Steps:
      1. Run: uv run python -c "from pykoclaw.scheduling import compute_next_run; print(compute_next_run('bogus', 'anything'))"
      2. Assert: output is "None"
    Expected Result: Unknown types return None, not the raw value
    Evidence: Terminal output captured

  Scenario: "once" schedule type still works
    Tool: Bash
    Steps:
      1. Run: uv run python -c "from pykoclaw.scheduling import compute_next_run; print(compute_next_run('once', '2025-03-01T12:00:00'))"
      2. Assert: output is "2025-03-01T12:00:00"
    Expected Result: Once type returns the value as-is
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix: handle "once" explicitly in compute_next_run, return None for unknown types`
  - Files: `pykoclaw/src/pykoclaw/scheduling.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 6. Fix handler.py global regex cache (Review item #10)

  **What to do**:
  - Replace the module-global `_HARD_MENTION_RE: re.Pattern[str] | None = None` with a dict cache keyed on trigger_name
  - Change `_is_hard_mention()` to look up the cache by trigger_name, building if absent
  - Add a test in `test_handler.py` that calls `_is_hard_mention` with different trigger names to verify the cache works correctly

  **Must NOT do**:
  - Do not change the regex pattern itself
  - Do not change the `_build_hard_mention_re` function
  - Do not change `MessageHandler` class

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small cache pattern change + one test
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py:33-59` — The global cache and `_is_hard_mention` function
  - `pykoclaw-whatsapp/tests/test_handler.py:351-361` — Existing `test_is_hard_mention_unit` test to extend

  **Acceptance Criteria**:
  - [ ] No module-global `_HARD_MENTION_RE` variable exists
  - [ ] A `_HARD_MENTION_CACHE: dict[str, re.Pattern[str]]` exists instead
  - [ ] `_is_hard_mention()` uses the dict cache keyed on trigger_name
  - [ ] New test verifies different trigger names produce correct results
  - [ ] `uv run pytest pykoclaw-whatsapp/tests/test_handler.py --tb=short -q` → all pass
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Different trigger names work correctly
    Tool: Bash
    Steps:
      1. Run: uv run python -c "
         from pykoclaw_whatsapp.handler import _is_hard_mention
         assert _is_hard_mention('@Andy check', 'Andy')
         assert not _is_hard_mention('@Andy check', 'Bob')
         assert _is_hard_mention('@Bob check', 'Bob')
         print('OK')"
      2. Assert: prints "OK"
    Expected Result: Cache handles multiple trigger names
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix(whatsapp): key regex cache on trigger_name to support config changes`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py`, `pykoclaw-whatsapp/tests/test_handler.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 7. Minor cleanups: chr(10) + dedent alias (Review items #12, #15)

  **What to do**:
  - **#12**: In `handler.py` line 166, change `{chr(10).join(lines)}` to use `"\n".join(lines)` outside the f-string
  - **#15**: In `connection.py`, remove the local `from textwrap import dedent as _dedent` inside `_build_system_prompt`. Add `from textwrap import dedent` at module top (check if already there). Replace `_dedent(` with `dedent(` in the method.

  **Must NOT do**:
  - Do not change any logic in either file
  - Do not touch other string formatting

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Two trivial readability fixes
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py:166` — The `chr(10)` line
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:147` — The local `_dedent` alias

  **Acceptance Criteria**:
  - [ ] `handler.py` has no `chr(10)` calls
  - [ ] `connection.py` has no `_dedent` alias — uses `dedent` from module-level import
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: No chr(10) or _dedent remain
    Tool: Bash
    Steps:
      1. Run: grep -c "chr(10)" pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py
      2. Assert: output is "0"
      3. Run: grep -c "_dedent" pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py
      4. Assert: output is "0"
    Expected Result: Both readability issues fixed
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `style(whatsapp): replace chr(10) with newline, remove local dedent alias`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py`, `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 8. Fix agent_core.py return type (Review item #13)

  **What to do**:
  - Change `from collections.abc import AsyncIterator` to `from collections.abc import AsyncGenerator`
  - Change return annotation of `query_agent` from `AsyncIterator[AgentMessage]` to `AsyncGenerator[AgentMessage, None]`

  **Must NOT do**:
  - Do not change any logic in query_agent
  - Do not change any other type annotations

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Two-line change
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw/src/pykoclaw/agent_core.py:6,56` — Import and return annotation

  **Acceptance Criteria**:
  - [ ] `agent_core.py` imports `AsyncGenerator` from `collections.abc`
  - [ ] `query_agent` return type is `AsyncGenerator[AgentMessage, None]`
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Return type annotation is correct
    Tool: Bash
    Steps:
      1. Run: grep "AsyncGenerator" pykoclaw/src/pykoclaw/agent_core.py
      2. Assert: output contains "AsyncGenerator"
      3. Run: uv run python -c "from pykoclaw.agent_core import query_agent; print('OK')"
      4. Assert: prints "OK"
    Expected Result: Type annotation updated, module importable
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix: use AsyncGenerator return type for query_agent`
  - Files: `pykoclaw/src/pykoclaw/agent_core.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 9. Fix inconsistent lazy imports in whatsapp __init__.py (Review item #14)

  **What to do**:
  - Move `import asyncio` from inside `register_commands` to module top level
  - It's stdlib and lightweight — no reason to lazy-import it
  - The heavy imports (neonize, connection, auth) should stay lazy inside subcommands — that's intentional

  **Must NOT do**:
  - Do not move heavy imports (neonize, connection, auth, handler) to top level — they're lazy for a reason
  - Do not change any logic

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Move one import line
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py:21` — `import asyncio` inside method

  **Acceptance Criteria**:
  - [ ] `asyncio` imported at module top level in `__init__.py`
  - [ ] No `import asyncio` inside `register_commands`
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: asyncio imported at top level
    Tool: Bash
    Steps:
      1. Run: head -15 pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py
      2. Assert: "import asyncio" appears in the top imports
      3. Run: grep -n "import asyncio" pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py
      4. Assert: only one occurrence, near the top of file
    Expected Result: Single top-level asyncio import
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `style(whatsapp): move asyncio import to module top level`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 10. Fix WhatsApp config data directory alignment (Review item #6)

  **What to do**:
  - In `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py`, change the defaults:
    - `auth_dir`: `Path.home() / ".pykoclaw" / "whatsapp" / "auth"` → `Path.home() / ".local" / "share" / "pykoclaw" / "whatsapp" / "auth"`
    - `session_db`: `Path.home() / ".pykoclaw" / "whatsapp" / "session.db"` → `Path.home() / ".local" / "share" / "pykoclaw" / "whatsapp" / "session.db"`
  - Update the README to reflect the new default paths
  - Update the whatsapp config tests that assert the old default paths

  **Must NOT do**:
  - Do not add migration logic for existing `~/.pykoclaw/` dirs
  - Do not import core `settings.data` — keep defaults self-contained (users can override via env vars)
  - Do not change env var names

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Config defaults + test updates
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py:14-18` — Default paths to change
  - `pykoclaw/src/pykoclaw/config.py:17` — Core data dir: `Path.home() / ".local" / "share" / "pykoclaw"` — the standard to match
  - `pykoclaw-whatsapp/tests/test_config.py:29-49` — Tests asserting old default paths — must update

  **Acceptance Criteria**:
  - [ ] `config.py` defaults use `~/.local/share/pykoclaw/whatsapp/` not `~/.pykoclaw/whatsapp/`
  - [ ] `test_config.py` tests updated to expect new paths
  - [ ] `uv run pytest pykoclaw-whatsapp/tests/test_config.py --tb=short -q` → all pass
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: WhatsApp defaults align with core data dir
    Tool: Bash
    Steps:
      1. Run: uv run python -c "
         from pykoclaw_whatsapp.config import WhatsAppSettings
         s = WhatsAppSettings()
         assert '.local/share/pykoclaw/whatsapp' in str(s.auth_dir)
         assert '.local/share/pykoclaw/whatsapp' in str(s.session_db)
         print('OK')"
      2. Assert: prints "OK"
    Expected Result: Defaults use XDG-compliant paths
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix(whatsapp): align config defaults to ~/.local/share/pykoclaw/whatsapp/`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py`, `pykoclaw-whatsapp/tests/test_config.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 11. Fix type hints: sqlite3.Connection → DbConnection (Review item #7)

  **What to do**:
  - Use `DbConnection` (already defined at `db.py:59`) in all function signatures that accept the db connection
  - Files to update:
    - `pykoclaw/src/pykoclaw/__main__.py:13` — return type annotation
    - `pykoclaw/src/pykoclaw/agent_core.py:49` — `db` parameter
    - `pykoclaw/src/pykoclaw/tools.py:18` — `db` parameter of `make_mcp_server`
    - `pykoclaw/src/pykoclaw/scheduler.py:18,67` — `db` parameters of `run_task`, `run_scheduler`
    - `pykoclaw/src/pykoclaw/plugins.py:24-25,91` — Protocol method `get_mcp_servers` and `run_db_migrations`
  - Add `from pykoclaw.db import DbConnection` import to each file
  - For the Plugin Protocol in `plugins.py`, change `db: sqlite3.Connection` to `db: DbConnection` — this is a public API change but all implementations already accept ThreadSafeConnection
  - Update WhatsApp plugin signatures too: `__init__.py:94`, `handler.py` functions, `connection.py`

  **Must NOT do**:
  - Do not change any logic or behavior
  - Do not change the `DbConnection` type alias definition itself
  - Do not add overload signatures or type: ignore annotations

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Cross-cutting but mechanical — find-and-replace type annotations across files
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw/src/pykoclaw/db.py:59` — `DbConnection = sqlite3.Connection | ThreadSafeConnection` — the type to use
  - `pykoclaw/src/pykoclaw/plugins.py:24` — Protocol method signature (public API)
  - `pykoclaw/src/pykoclaw/__main__.py:13` — Return type to fix
  - `pykoclaw/src/pykoclaw/agent_core.py:49` — Parameter type to fix
  - `pykoclaw/src/pykoclaw/tools.py:18` — Parameter type to fix
  - `pykoclaw/src/pykoclaw/scheduler.py:18,67` — Parameter types to fix
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py:94` — Plugin method signature
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py` — DB function signatures
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py` — DB parameter

  **Acceptance Criteria**:
  - [ ] No function in pykoclaw core annotates db as bare `sqlite3.Connection` (except inside db.py itself)
  - [ ] `from pykoclaw.db import DbConnection` appears in all files that use the type
  - [ ] Plugin Protocol uses `DbConnection` in `get_mcp_servers`
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: No bare sqlite3.Connection in function signatures (except db.py)
    Tool: Bash
    Steps:
      1. Run: grep -rn "sqlite3.Connection" pykoclaw/src/pykoclaw/ --include="*.py" | grep -v "db.py" | grep -v __pycache__
      2. Assert: no output (all converted to DbConnection)
      3. Run: uv run python -c "from pykoclaw.plugins import PykoClawPlugin; print('OK')"
      4. Assert: prints "OK"
    Expected Result: All type hints updated
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix: use DbConnection type alias consistently across all packages`
  - Files: Multiple (see list above)
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 12. Rename `id` → `task_id` in db.py function parameters (Review item #16)

  **What to do**:
  - In `db.py`, rename the `id` parameter to `task_id` in: `create_task`, `get_task`, `update_task`, `delete_task`, `update_task_after_run`
  - Update all internal references to the parameter within each function body
  - Update all callers:
    - `pykoclaw/src/pykoclaw/tools.py` — `create_task(db, id=task_id, ...)`, `get_task(db, task_id)`, `update_task(db, args["task_id"], ...)`, `delete_task(db, args["task_id"])`
    - `pykoclaw/src/pykoclaw/scheduler.py` — `update_task_after_run(db, task.id, ...)`, `log_task_run(db, task_id=task.id, ...)`
  - **DO NOT rename `ScheduledTask.id` field** in models.py — that maps to the DB column

  **Must NOT do**:
  - Do not rename the `id` field in `ScheduledTask` model (models.py)
  - Do not change the `id` column in SQL
  - Do not change the `task_id` parameter in `log_task_run` (it's already correctly named)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Mechanical rename, but with blast radius across callers
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw/src/pykoclaw/db.py:137-259` — All functions using `id` parameter
  - `pykoclaw/src/pykoclaw/tools.py:37-118` — Callers passing `id=` keyword arg
  - `pykoclaw/src/pykoclaw/scheduler.py:55-63` — Callers using `task.id`
  - `pykoclaw/src/pykoclaw/models.py:12` — `ScheduledTask.id` — DO NOT CHANGE
  - `pykoclaw/tests/test_db.py` — Tests that call these functions with `id=` keyword

  **Acceptance Criteria**:
  - [ ] No function in `db.py` has a parameter named `id` (only `task_id`)
  - [ ] `log_task_run` parameter stays `task_id` (was already correct)
  - [ ] `ScheduledTask.id` model field unchanged in models.py
  - [ ] All callers in `tools.py`, `scheduler.py`, tests updated
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: No id parameter in db.py function signatures
    Tool: Bash
    Steps:
      1. Run: grep -n "def.*\bid\b.*:" pykoclaw/src/pykoclaw/db.py | grep -v task_id | grep -v "# "
      2. Assert: no output (all renamed to task_id)
      3. Run: grep "ScheduledTask" pykoclaw/src/pykoclaw/models.py | head -5
      4. Assert: model still has `id: str` field
    Expected Result: Parameters renamed, model untouched
    Evidence: Terminal output captured

  Scenario: Callers updated correctly
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw/tests/test_db.py -v --tb=short
      2. Assert: all tests pass
      3. Run: uv run pytest pykoclaw/tests/test_tools.py -v --tb=short
      4. Assert: all tests pass
    Expected Result: All callers work with renamed parameter
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `refactor: rename id → task_id in db.py function parameters`
  - Files: `pykoclaw/src/pykoclaw/db.py`, `pykoclaw/src/pykoclaw/tools.py`, `pykoclaw/src/pykoclaw/scheduler.py`, `pykoclaw/tests/test_db.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

- [x] 13. Remove dead protocol methods (Review item #17)

  **What to do**:
  - Remove `on_message`, `on_startup`, `on_shutdown` from the `PykoClawPlugin` Protocol class
  - Remove the same methods from `PykoClawPluginBase` base class
  - Update tests in `test_plugins.py` that test these methods (remove the assertions)

  **Must NOT do**:
  - Do not add lifecycle hook call sites
  - Do not touch `get_config_class` (it IS used by whatsapp plugin)
  - Do not change `register_commands`, `get_mcp_servers`, `get_db_migrations` — these are actively used

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Delete methods, update tests
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: None
  - **Blocked By**: Task 0

  **References**:
  - `pykoclaw/src/pykoclaw/plugins.py:38-48,68-75` — Methods to remove from Protocol and base class
  - `pykoclaw/tests/test_plugins.py:46-53` — Test assertions to remove

  **Acceptance Criteria**:
  - [ ] `PykoClawPlugin` Protocol has no `on_message`, `on_startup`, `on_shutdown` methods
  - [ ] `PykoClawPluginBase` has no `on_message`, `on_startup`, `on_shutdown` methods
  - [ ] Tests updated (no assertions about removed methods)
  - [ ] `uv run pytest pykoclaw/tests/test_plugins.py --tb=short -q` → all pass
  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Dead methods removed
    Tool: Bash
    Steps:
      1. Run: grep -c "on_message\|on_startup\|on_shutdown" pykoclaw/src/pykoclaw/plugins.py
      2. Assert: output is "0"
      3. Run: uv run python -c "from pykoclaw.plugins import PykoClawPluginBase; p = PykoClawPluginBase(); assert not hasattr(p, 'on_message'); print('OK')"
      4. Assert: prints "OK"
    Expected Result: Dead protocol surface removed
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `refactor: remove unused on_message/on_startup/on_shutdown from plugin protocol`
  - Files: `pykoclaw/src/pykoclaw/plugins.py`, `pykoclaw/tests/test_plugins.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`

---

## Commit Strategy

| After Task | Message | Key Files | Verification |
|------------|---------|-----------|--------------|
| 1 | `fix: delete dead agent.py superseded by agent_core.py` | agent.py (deleted) | pytest |
| 2 | `fix(whatsapp): add thread-safety to OutgoingQueue, use deque, remove orphan field` | queue.py | pytest |
| 3 | `fix(whatsapp): replace broken async auth with threading.Event pattern` | auth.py, __init__.py | pytest |
| 4 | `fix: preserve next_run for recurring tasks on error` | scheduler.py, test_scheduler.py | pytest |
| 5 | `fix: handle "once" explicitly in compute_next_run, return None for unknown` | scheduling.py | pytest |
| 6 | `fix(whatsapp): key regex cache on trigger_name to support config changes` | handler.py, test_handler.py | pytest |
| 7 | `style(whatsapp): replace chr(10) with newline, remove local dedent alias` | handler.py, connection.py | pytest |
| 8 | `fix: use AsyncGenerator return type for query_agent` | agent_core.py | pytest |
| 9 | `style(whatsapp): move asyncio import to module top level` | __init__.py | pytest |
| 10 | `fix(whatsapp): align config defaults to ~/.local/share/pykoclaw/whatsapp/` | config.py, test_config.py | pytest |
| 11 | `fix: use DbConnection type alias consistently across all packages` | ~8 files | pytest |
| 12 | `refactor: rename id → task_id in db.py function parameters` | db.py, tools.py, scheduler.py, test_db.py | pytest |
| 13 | `refactor: remove unused on_message/on_startup/on_shutdown from plugin protocol` | plugins.py, test_plugins.py | pytest |

---

## Success Criteria

### Verification Commands
```bash
uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q
# Expected: ≥112 tests passed, 0 failed (110 baseline + new tests for #5 and #10)

git log --oneline -13
# Expected: 13 commits matching the strategy above
```

### Final Checklist
- [x] All 18 review items addressed
- [x] All tests pass
- [x] No SQLite schema changes
- [x] No new dependencies added
- [x] `ScheduledTask.id` model field unchanged
- [x] Commit messages follow conventional format
