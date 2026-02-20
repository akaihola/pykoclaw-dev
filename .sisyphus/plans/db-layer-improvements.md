# DB Layer Improvements — Quick Wins

## Status: Done

## TL;DR

> **Quick Summary**: Four targeted refactoring improvements to the raw-SQL database layer: extract a row-to-model helper, add a missing Pydantic model, unify type annotations across packages, and introduce a transaction context manager.
>
> **Deliverables**:
> - `_rows_to()` generic helper in `db.py`
> - `TaskRunLog` Pydantic model in `models.py`
> - `DbConnection` type annotations replacing `sqlite3.Connection` across production code
> - `transaction()` context manager on `ThreadSafeConnection`
>
> **Estimated Effort**: Quick (<2h total)
> **Parallel Execution**: NO — sequential (each builds naturally on prior, and user wants frequent commits)
> **Critical Path**: Task 0 (baseline) → Task 1 → Task 2 → Task 3 → Task 4

---

## Context

### Original Request
User asked Oracle whether an ORM would simplify the codebase. Oracle recommended **against** an ORM (the DB layer is ~260 lines with 3 tables — well within the "just right" zone for raw SQL). Oracle instead identified 4 quick-win improvements to the existing layer. User asked for a plan covering all 4, with frequent commits.

### Metis Review
**Identified Gaps** (addressed in this plan):
- `scheduler.py` and core files (`plugins.py`, `agent_core.py`, `tools.py`, `__main__.py`) also use `sqlite3.Connection` — Task 3 scope expanded to include these
- `get_new_messages_for_chat` in handler.py is NOT a `_rows_to()` candidate (returns tuples, not models) — explicitly excluded from Task 1
- Task 4's `ThreadSafeConnection` uses non-reentrant `threading.Lock` — plan requires `transaction()` to hold the lock and operate on raw `self._conn` directly to avoid deadlock
- `plugins.py` defines the `PykoClawPlugin` protocol with `sqlite3.Connection` — changing this is a **public API change** that affects all plugins, so Task 3 must handle it carefully (the union type `DbConnection` already accepts `sqlite3.Connection`, so this is backward-compatible)

---

## Work Objectives

### Core Objective
Improve the DB layer's consistency, type safety, and DRYness without changing any runtime behavior.

### Concrete Deliverables
- Helper function `_rows_to()` in `pykoclaw/src/pykoclaw/db.py`
- Model class `TaskRunLog` in `pykoclaw/src/pykoclaw/models.py`
- `DbConnection` annotations in 7 production files across 2 packages
- `transaction()` context manager on `ThreadSafeConnection` + `delete_task()` converted

### Definition of Done
- [x] All existing tests pass unchanged: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ -v`
- [x] 4 clean atomic commits, one per improvement
- [x] No behavioral changes (same return types, same side effects, same error handling)

### Must Have
- Each improvement is a separate commit with descriptive message
- All tests pass after EACH commit (verified by executor)
- Type annotations use the `DbConnection` union type consistently

### Must NOT Have (Guardrails)
- **No new query functions** — don't add `get_task_run_logs()` or similar
- **No test file annotation changes** — test fixtures correctly use `sqlite3.Connection` directly, which is valid as part of the `DbConnection` union
- **No singleton helper** — don't create `_row_to()` for `get_conversation`/`get_task` (only 2 call sites, not worth it)
- **No single-statement transaction wrapping** — only convert multi-statement functions (`delete_task`) to use `transaction()`; single-execute-then-commit functions stay as-is
- **No pre-existing bug fixes** — e.g., `test_db.py` fixture annotation says `sqlite3.Connection` but `init_db()` returns `ThreadSafeConnection`; this is a pre-existing mismatch — do NOT fix it
- **No `import sqlite3` cleanup** — if `import sqlite3` becomes unused after annotation changes, leave it (it may be used for `sqlite3.Row` or other runtime references)

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks are verified by running commands. No human action required.

### Test Decision
- **Infrastructure exists**: YES (`pytest` in dev dependencies, `test_db.py` + WhatsApp test files)
- **Automated tests**: Tests-after (existing tests must keep passing; no new tests needed for pure refactors)
- **Framework**: `pytest` via `uv run`

### Baseline Capture (Task 0)
Before ANY changes, run:
```bash
uv run pytest pykoclaw/tests/ -v
uv run pytest pykoclaw-whatsapp/tests/ -v
```
Capture output. These must produce identical pass/fail results after ALL changes.

---

## Execution Strategy

### Sequential Execution (user requested frequent commits)

```
Task 0: Capture baseline test results
  ↓
Task 1: Extract _rows_to() helper → commit
  ↓
Task 2: Add TaskRunLog model → commit
  ↓
Task 3: Unify DbConnection annotations → commit
  ↓
Task 4: Add transaction() context manager → commit
  ↓
Task 5: Final verification
```

### Dependency Matrix

| Task | Depends On | Blocks | Commit |
|------|------------|--------|--------|
| 0 | None | 1 | NO |
| 1 | 0 | 2 | YES |
| 2 | 1 | 3 | YES |
| 3 | 2 | 4 | YES |
| 4 | 3 | 5 | YES |
| 5 | 4 | None | NO |

---

## TODOs

- [x] 0. Capture baseline test results

  **What to do**:
  - Run `uv run pytest pykoclaw/tests/ -v` and capture output
  - Run `uv run pytest pykoclaw-whatsapp/tests/ -v` and capture output
  - Note the exact test count and pass/fail status

  **Must NOT do**:
  - Change any code
  - Fix any pre-existing test failures

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single command execution, no code changes
  - **Skills**: [`git-master`]
    - `git-master`: Needed for the commit workflow in subsequent tasks

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (first task)
  - **Blocks**: Tasks 1-5
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `pykoclaw/tests/test_db.py` — All core DB tests (5 test functions)
  - `pykoclaw-whatsapp/tests/test_handler.py` — WhatsApp handler tests
  - `pykoclaw-whatsapp/tests/test_connection.py` — WhatsApp connection tests

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Capture core test baseline
    Tool: Bash
    Preconditions: uv workspace set up, dependencies installed
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ -v
      2. Capture exact test count and pass/fail
      3. Assert: all tests pass (0 failures)
    Expected Result: All core tests pass
    Evidence: Terminal output captured

  Scenario: Capture WhatsApp test baseline
    Tool: Bash
    Preconditions: uv workspace set up, dependencies installed
    Steps:
      1. Run: uv run pytest pykoclaw-whatsapp/tests/ -v
      2. Capture exact test count and pass/fail
      3. Assert: all tests pass (0 failures)
    Expected Result: All WhatsApp tests pass
    Evidence: Terminal output captured
  ```

  **Commit**: NO

---

- [x] 1. Extract `_rows_to()` generic helper

  **What to do**:
  - Add `from typing import TypeVar` (or use existing import) and a `TypeVar` bound to `BaseModel` at module level in `db.py`
  - Create private helper function `_rows_to()` in `db.py`:
    ```python
    ModelT = TypeVar("ModelT", bound=BaseModel)

    def _rows_to(model: type[ModelT], rows: list[sqlite3.Row]) -> list[ModelT]:
        return [model(**row) for row in rows]
    ```
  - Replace the 4 list-comprehension patterns in `db.py`:
    - `list_conversations` (line 134): `[Conversation(**row) for row in rows]` → `_rows_to(Conversation, rows)`
    - `get_tasks_for_conversation` (line 181): `[ScheduledTask(**row) for row in rows]` → `_rows_to(ScheduledTask, rows)`
    - `get_all_tasks` (line 188): `[ScheduledTask(**row) for row in rows]` → `_rows_to(ScheduledTask, rows)`
    - `get_due_tasks` (line 224): `[ScheduledTask(**row) for row in rows]` → `_rows_to(ScheduledTask, rows)`
  - Add `from pydantic import BaseModel` import in `db.py` (needed for the `TypeVar` bound)
  - Run tests to verify

  **Must NOT do**:
  - Create a `_row_to()` for singleton lookups (`get_conversation`, `get_task`) — only 2 sites, not worth it
  - Touch `handler.py`'s `get_new_messages_for_chat` — it returns tuples, not models (different pattern)
  - Change any function signatures or return types
  - Make `_rows_to()` public (keep underscore prefix)
  - Move it to `models.py` — keep it in `db.py` as a private helper

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple refactor in a single file, 4 mechanical replacements
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit with proper message

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: Task 2
  - **Blocked By**: Task 0

  **References**:

  **Pattern References**:
  - `pykoclaw/src/pykoclaw/db.py:134` — `list_conversations`: `[Conversation(**row) for row in rows]`
  - `pykoclaw/src/pykoclaw/db.py:181` — `get_tasks_for_conversation`: same pattern with `ScheduledTask`
  - `pykoclaw/src/pykoclaw/db.py:188` — `get_all_tasks`: same pattern
  - `pykoclaw/src/pykoclaw/db.py:224` — `get_due_tasks`: same pattern

  **API/Type References**:
  - `pykoclaw/src/pykoclaw/models.py:1` — `BaseModel` import (the bound for the TypeVar)

  **WHY Each Reference Matters**:
  - Lines 134, 181, 188, 224 are the EXACT 4 sites to replace. The executor must confirm these are the only list-pattern sites before proceeding.
  - `models.py` shows the `BaseModel` base class that all models extend.

  **Acceptance Criteria**:

  - [ ] `_rows_to` function exists in `db.py` with correct generic signature
  - [ ] Zero remaining `[Model(**row) for row in rows]` patterns in `db.py`
  - [ ] `uv run pytest pykoclaw/tests/test_db.py -v` → all tests pass

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Helper function exists and works
    Tool: Bash
    Preconditions: Changes applied to db.py
    Steps:
      1. Run: uv run python -c "from pykoclaw.db import _rows_to; print('import OK')"
      2. Assert: output contains "import OK"
    Expected Result: Helper is importable
    Evidence: Terminal output

  Scenario: No remaining raw list comprehension patterns
    Tool: Bash
    Preconditions: Changes applied
    Steps:
      1. Run: grep -c 'for row in rows' pykoclaw/src/pykoclaw/db.py
      2. Assert: count is 1 (only inside _rows_to itself)
    Expected Result: All call sites converted
    Evidence: grep output

  Scenario: Core tests still pass
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ -v
      2. Assert: same test count as baseline, 0 failures
    Expected Result: All tests pass
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `refactor(db): extract _rows_to() helper to DRY row-to-model conversion`
  - Files: `pykoclaw/src/pykoclaw/db.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/test_db.py -v`

---

- [x] 2. Add `TaskRunLog` Pydantic model

  **What to do**:
  - Add `TaskRunLog` class to `pykoclaw/src/pykoclaw/models.py`:
    ```python
    class TaskRunLog(BaseModel):
        id: int
        task_id: str
        run_at: str
        duration_ms: int
        status: str
        result: str | None = None
        error: str | None = None
    ```
  - Note: `id` is `int` (not `str`) because `task_run_logs.id` is `INTEGER PRIMARY KEY AUTOINCREMENT`
  - Update `db.py` import to include `TaskRunLog`: `from pykoclaw.models import Conversation, ScheduledTask, TaskRunLog`
  - Run tests to verify

  **Must NOT do**:
  - Add any query functions that return `TaskRunLog` (like `get_task_run_logs()`)
  - Modify `log_task_run()` to return the model
  - Update `test_log_task_run` to use the model
  - Change any existing model classes

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Adding a single class to a 23-line file + one import update
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: Task 3
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `pykoclaw/src/pykoclaw/models.py:1-23` — Existing model patterns (`Conversation`, `ScheduledTask`): `BaseModel` subclass with `str | None` for optional fields

  **API/Type References**:
  - `pykoclaw/src/pykoclaw/db.py:77-89` — `task_run_logs` CREATE TABLE schema: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `task_id TEXT NOT NULL`, `run_at TEXT NOT NULL`, `duration_ms INTEGER NOT NULL`, `status TEXT NOT NULL`, `result TEXT`, `error TEXT`

  **WHY Each Reference Matters**:
  - `models.py` shows the exact style convention for model classes (follow identical patterns)
  - `db.py:77-89` is the authoritative schema — model fields MUST match column names, types, and nullability exactly

  **Acceptance Criteria**:

  - [ ] `TaskRunLog` class exists in `models.py` with 7 fields matching the DB schema
  - [ ] `id` field is `int`, not `str`
  - [ ] `result` and `error` are `str | None` with default `None`
  - [ ] Import added to `db.py` (even though no function uses it yet — establishes the pattern)
  - [ ] `uv run pytest pykoclaw/tests/ -v` → all tests pass

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Model is importable and has correct fields
    Tool: Bash
    Steps:
      1. Run: uv run python -c "
         from pykoclaw.models import TaskRunLog
         t = TaskRunLog(id=1, task_id='t1', run_at='2024-01-01T00:00:00Z', duration_ms=100, status='success')
         assert t.id == 1
         assert isinstance(t.id, int)
         assert t.result is None
         assert t.error is None
         print('OK')
         "
      2. Assert: output contains "OK"
    Expected Result: Model instantiates correctly
    Evidence: Terminal output

  Scenario: Core tests still pass
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ -v
      2. Assert: same test count as baseline, 0 failures
    Expected Result: All tests pass
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `feat(models): add TaskRunLog Pydantic model for task_run_logs table`
  - Files: `pykoclaw/src/pykoclaw/models.py`, `pykoclaw/src/pykoclaw/db.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/test_db.py -v`

---

- [x] 3. Unify `DbConnection` type annotations across production code

  **What to do**:
  - Change `sqlite3.Connection` → `DbConnection` in **production code only** across these files:

  **Core package (`pykoclaw/src/pykoclaw/`):**
  - `scheduler.py` lines 18, 71: `db: sqlite3.Connection` → `db: DbConnection`; add `from pykoclaw.db import DbConnection`; remove `import sqlite3` if now unused
  - `plugins.py` lines 25, 58, 91: `db: sqlite3.Connection` → `db: DbConnection`; add `from pykoclaw.db import DbConnection`; remove `import sqlite3` if now unused — **NOTE**: This changes the `PykoClawPlugin` Protocol and `PykoClawPluginBase`. Since `DbConnection = sqlite3.Connection | ThreadSafeConnection`, existing plugins passing `sqlite3.Connection` still satisfy the type. This is backward-compatible.
  - `agent_core.py` line 49: `db: sqlite3.Connection` → `db: DbConnection`; add import
  - `tools.py` line 18: `db: sqlite3.Connection` → `db: DbConnection`; add import
  - `__main__.py` line 13: return type annotation `sqlite3.Connection` → `DbConnection`; add import

  **WhatsApp plugin (`pykoclaw-whatsapp/src/pykoclaw_whatsapp/`):**
  - `handler.py` lines 169, 186, 198, 210, 224, 255: `db: sqlite3.Connection` → `db: DbConnection`; add `from pykoclaw.db import DbConnection`; keep `import sqlite3` if used for other things (check if `sqlite3` is used at runtime beyond annotations)
  - `connection.py` line 66: `db: sqlite3.Connection` → `db: DbConnection`; add import
  - `__init__.py` line 92: `db: sqlite3.Connection` → `db: DbConnection`; add import

  **Important**: For each file, after changing the annotation:
  1. Check if `import sqlite3` is still needed for runtime use (e.g., `sqlite3.connect()`, `sqlite3.Row`)
  2. If ONLY used for the type annotation, remove the `import sqlite3` line
  3. If used for both, keep the import

  **Must NOT do**:
  - Change test file annotations (`test_db.py`, `test_handler.py`, `test_connection.py`, `test_scheduler.py`, `test_plugins.py`, `test_tools.py`)
  - Change any function behavior, only type annotations
  - Add `from __future__ import annotations` to files that don't already have it (changing annotation semantics is out of scope)
  - Create circular imports (verify by running the import)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Mechanical annotation changes across multiple files, all following the same pattern
  - **Skills**: [`git-master`]
    - `git-master`: Atomic commit for cross-file change

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: Task 4
  - **Blocked By**: Task 2

  **References**:

  **Pattern References**:
  - `pykoclaw/src/pykoclaw/db.py:59` — `DbConnection = sqlite3.Connection | ThreadSafeConnection` — the type alias to use everywhere

  **API/Type References**:
  - `pykoclaw/src/pykoclaw/plugins.py:17-48` — `PykoClawPlugin` Protocol definition — changing `sqlite3.Connection` → `DbConnection` here is backward-compatible because the union accepts both types
  - `pykoclaw/src/pykoclaw/plugins.py:51-75` — `PykoClawPluginBase` base class — same change needed

  **Files to change** (exhaustive list from grep results):
  - `pykoclaw/src/pykoclaw/scheduler.py` — 2 annotations (lines 18, 71)
  - `pykoclaw/src/pykoclaw/plugins.py` — 3 annotations (lines 25, 58, 91)
  - `pykoclaw/src/pykoclaw/agent_core.py` — 1 annotation (line 49)
  - `pykoclaw/src/pykoclaw/tools.py` — 1 annotation (line 18)
  - `pykoclaw/src/pykoclaw/__main__.py` — 1 annotation (line 13)
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py` — 6 annotations (lines 169, 186, 198, 210, 224, 255)
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py` — 1 annotation (line 66)
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py` — 1 annotation (line 92)

  **WHY Each Reference Matters**:
  - `db.py:59` defines `DbConnection` — this is THE type to use; executor must import it
  - `plugins.py` Protocol is the public API for plugin authors — the change MUST be backward-compatible
  - The 8 files listed above are the EXACT scope; executor should NOT change any files not listed

  **Acceptance Criteria**:

  - [ ] Zero `db: sqlite3.Connection` annotations in production code (8 files listed above)
  - [ ] All changed files import `DbConnection` from `pykoclaw.db`
  - [ ] `uv run pytest pykoclaw/tests/ -v` → all tests pass
  - [ ] `uv run pytest pykoclaw-whatsapp/tests/ -v` → all tests pass

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: No sqlite3.Connection annotations in production code
    Tool: Bash
    Steps:
      1. Run: grep -rn 'db: sqlite3.Connection' pykoclaw/src/ pykoclaw-whatsapp/src/
      2. Assert: output is empty (0 matches)
    Expected Result: All production annotations converted
    Evidence: grep output (should be empty)

  Scenario: No circular imports
    Tool: Bash
    Steps:
      1. Run: uv run python -c "from pykoclaw.plugins import PykoClawPlugin; print('OK')"
      2. Run: uv run python -c "from pykoclaw_whatsapp.handler import store_message; print('OK')"
      3. Assert: both outputs contain "OK"
    Expected Result: All imports resolve without circular dependency
    Evidence: Terminal output

  Scenario: Full test suite passes
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ -v
      2. Run: uv run pytest pykoclaw-whatsapp/tests/ -v
      3. Assert: same test count as baseline, 0 failures in both
    Expected Result: All tests pass
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `refactor(types): unify sqlite3.Connection → DbConnection across production code`
  - Files: `pykoclaw/src/pykoclaw/scheduler.py`, `pykoclaw/src/pykoclaw/plugins.py`, `pykoclaw/src/pykoclaw/agent_core.py`, `pykoclaw/src/pykoclaw/tools.py`, `pykoclaw/src/pykoclaw/__main__.py`, `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py`, `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`, `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ -v`

---

- [x] 4. Add `transaction()` context manager to `ThreadSafeConnection`

  **What to do**:
  - Add a `transaction()` context manager method to `ThreadSafeConnection` in `db.py`:
    ```python
    from contextlib import contextmanager
    from collections.abc import Iterator

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        """Acquire lock, yield raw connection, commit on success / rollback on error."""
        self._lock.acquire()
        try:
            yield self._conn
            self._conn.commit()
        except BaseException:
            self._conn.rollback()
            raise
        finally:
            self._lock.release()
    ```
  - **Key design**: The method acquires `self._lock` ONCE and yields the raw `self._conn` directly. This avoids deadlock (because individual `execute()` calls on `ThreadSafeConnection` also acquire the same lock). The caller operates on the raw connection within the CM, bypassing per-call locking.
  - Convert `delete_task()` to use it:
    ```python
    def delete_task(db: DbConnection, id: str) -> None:
        if isinstance(db, ThreadSafeConnection):
            with db.transaction() as conn:
                conn.execute("DELETE FROM task_run_logs WHERE task_id = ?", (id,))
                conn.execute("DELETE FROM scheduled_tasks WHERE id = ?", (id,))
        else:
            db.execute("DELETE FROM task_run_logs WHERE task_id = ?", (id,))
            db.execute("DELETE FROM scheduled_tasks WHERE id = ?", (id,))
            db.commit()
    ```
  - Run tests to verify

  **Must NOT do**:
  - Convert single-execute-then-commit functions to use `transaction()` — adds noise, not value
  - Change `threading.Lock` to `threading.RLock` — the `transaction()` method acquires the lock and yields the raw `_conn`, so no reentrant locking is needed
  - Add an `async` version — all DB access is synchronous
  - Add a standalone `transaction()` function for the union type — keep it as a method on `ThreadSafeConnection`; `delete_task` handles the `isinstance` check

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single method + one function conversion, well-defined
  - **Skills**: [`git-master`]
    - `git-master`: Final atomic commit

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (final task)
  - **Blocks**: Task 5
  - **Blocked By**: Task 3

  **References**:

  **Pattern References**:
  - `pykoclaw/src/pykoclaw/db.py:13-58` — `ThreadSafeConnection` class: understand the `_lock` and `_conn` attributes, the existing `commit()` and `rollback()` methods
  - `pykoclaw/src/pykoclaw/db.py:208-211` — `delete_task()`: the multi-statement function to convert (two `execute()` + one `commit()`)

  **API/Type References**:
  - `pykoclaw/src/pykoclaw/db.py:59` — `DbConnection` union type: `delete_task` must handle both `ThreadSafeConnection` (use transaction) and `sqlite3.Connection` (fallback to direct execute+commit)

  **WHY Each Reference Matters**:
  - `ThreadSafeConnection` internals (lines 13-58): The executor MUST understand that `_lock` is acquired per-call in `execute()`. The `transaction()` method bypasses this by acquiring the lock once and yielding `_conn` directly. This is the core design decision.
  - `delete_task` (lines 208-211): This is the ONLY function to convert. It's the clearest multi-statement transaction candidate (delete logs, then delete task — both must succeed or fail together).

  **Acceptance Criteria**:

  - [ ] `ThreadSafeConnection.transaction()` method exists and is a context manager
  - [ ] `transaction()` acquires lock, yields raw `_conn`, commits on success, rolls back on exception
  - [ ] `delete_task()` uses `transaction()` for `ThreadSafeConnection` instances
  - [ ] `uv run pytest pykoclaw/tests/test_db.py -v` → all tests pass (including `test_task_crud` which exercises `delete_task`)

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: transaction() exists on ThreadSafeConnection
    Tool: Bash
    Steps:
      1. Run: uv run python -c "
         from pykoclaw.db import ThreadSafeConnection
         assert hasattr(ThreadSafeConnection, 'transaction')
         print('OK')
         "
      2. Assert: output contains "OK"
    Expected Result: Method exists
    Evidence: Terminal output

  Scenario: transaction() commits on success
    Tool: Bash
    Steps:
      1. Run: uv run python -c "
         import sqlite3
         from pykoclaw.db import ThreadSafeConnection
         raw = sqlite3.connect(':memory:')
         db = ThreadSafeConnection(raw)
         db.execute('CREATE TABLE t (x TEXT)')
         db.commit()
         with db.transaction() as conn:
             conn.execute('INSERT INTO t VALUES (?)', ('hello',))
         row = db.execute('SELECT x FROM t').fetchone()
         assert row[0] == 'hello'
         print('OK')
         "
      2. Assert: output contains "OK"
    Expected Result: Data persisted after transaction
    Evidence: Terminal output

  Scenario: transaction() rolls back on error
    Tool: Bash
    Steps:
      1. Run: uv run python -c "
         import sqlite3
         from pykoclaw.db import ThreadSafeConnection
         raw = sqlite3.connect(':memory:')
         db = ThreadSafeConnection(raw)
         db.execute('CREATE TABLE t (x TEXT)')
         db.commit()
         try:
             with db.transaction() as conn:
                 conn.execute('INSERT INTO t VALUES (?)', ('oops',))
                 raise ValueError('boom')
         except ValueError:
             pass
         row = db.execute('SELECT count(*) FROM t').fetchone()
         assert row[0] == 0, f'Expected 0 rows, got {row[0]}'
         print('OK')
         "
      2. Assert: output contains "OK"
    Expected Result: Insert rolled back after exception
    Evidence: Terminal output

  Scenario: delete_task uses transaction (code inspection)
    Tool: Bash
    Steps:
      1. Run: grep -A10 'def delete_task' pykoclaw/src/pykoclaw/db.py
      2. Assert: output contains "transaction"
    Expected Result: delete_task references transaction()
    Evidence: grep output

  Scenario: Full test suite passes
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ -v
      2. Run: uv run pytest pykoclaw-whatsapp/tests/ -v
      3. Assert: same test count as baseline, 0 failures
    Expected Result: All tests pass
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `refactor(db): add transaction() context manager to ThreadSafeConnection`
  - Files: `pykoclaw/src/pykoclaw/db.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/test_db.py -v`

---

- [x] 5. Final cross-package verification

  **What to do**:
  - Run full test suite across both packages
  - Verify all 4 commits are clean and atomic
  - Verify `git log --oneline` shows 4 commits in order

  **Must NOT do**:
  - Make any code changes
  - Amend any commits

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Verification only
  - **Skills**: [`git-master`]
    - `git-master`: Log inspection

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (final)
  - **Blocks**: None
  - **Blocked By**: Task 4

  **References**: None (verification task)

  **Acceptance Criteria**:

  - [ ] `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ -v` → all pass
  - [ ] `git log --oneline -4` shows 4 commits with correct messages

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Full test suite passes
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ -v
      2. Assert: all tests pass, 0 failures
    Expected Result: Complete green suite
    Evidence: Terminal output

  Scenario: Commit history is clean
    Tool: Bash
    Steps:
      1. Run: git log --oneline -4
      2. Assert: 4 commits visible with messages matching:
         - "refactor(db): add transaction() context manager to ThreadSafeConnection"
         - "refactor(types): unify sqlite3.Connection → DbConnection across production code"
         - "feat(models): add TaskRunLog Pydantic model for task_run_logs table"
         - "refactor(db): extract _rows_to() helper to DRY row-to-model conversion"
    Expected Result: 4 atomic commits in correct order
    Evidence: git log output
  ```

  **Commit**: NO

---

## Commit Strategy

| After Task | Message | Key Files | Verification |
|------------|---------|-----------|--------------|
| 1 | `refactor(db): extract _rows_to() helper to DRY row-to-model conversion` | `db.py` | `uv run pytest pykoclaw/tests/test_db.py -v` |
| 2 | `feat(models): add TaskRunLog Pydantic model for task_run_logs table` | `models.py`, `db.py` | `uv run pytest pykoclaw/tests/ -v` |
| 3 | `refactor(types): unify sqlite3.Connection → DbConnection across production code` | 8 files | `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ -v` |
| 4 | `refactor(db): add transaction() context manager to ThreadSafeConnection` | `db.py` | `uv run pytest pykoclaw/tests/test_db.py -v` |

---

## Success Criteria

### Verification Commands
```bash
# All tests pass
uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ -v

# No sqlite3.Connection annotations in production code
grep -rn 'db: sqlite3.Connection' pykoclaw/src/ pykoclaw-whatsapp/src/
# Expected: empty output

# 4 clean commits
git log --oneline -4
```

### Final Checklist
- [x] `_rows_to()` helper exists and is used in all 4 list-return functions
- [x] `TaskRunLog` model exists with correct field types matching DB schema
- [x] Zero `db: sqlite3.Connection` annotations in production code
- [x] `transaction()` CM exists on `ThreadSafeConnection` with commit/rollback semantics
- [x] `delete_task()` uses `transaction()` for atomic multi-statement execution
- [x] All existing tests pass unchanged
- [x] 4 atomic commits with descriptive messages
