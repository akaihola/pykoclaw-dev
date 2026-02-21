# Core Package Simplification

## Status: Backlog
## Priority: 3

## TL;DR

> **Quick Summary**: Simplify `pykoclaw/src/pykoclaw/` — remove dead code,
> extract repeated patterns into helpers, de-duplicate logic, and fix a
> silent-discard bug. Seven focused changes that together save ~40 lines
> and reduce visual noise without altering any public API or plugin contract.
>
> **Deliverables**:
> - `tools.py`: `_text_response()` helper replaces 5 identical response dicts
> - `scheduler.py`: Extract duplicated `next_run` computation out of try/except branches
> - `db.py`: Remove unused `TaskRunLog` import
> - `db.py`: Fix `mark_delivery_failed()` — store the `error` string it accepts but silently discards
> - `models.py`: Remove `TaskRunLog` model (unused anywhere in the codebase)
> - `__init__.py`: Remove orphan `__version__` (duplicates `pyproject.toml`, never imported)
> - `agent_core.py`: Add docstring noting the generator currently buffers (no API change)
>
> **Estimated Effort**: Quick (< 1.5 hours)
> **Parallel Execution**: NO — sequential commits, each gated by tests
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 → Task 5 → Task 6 → Task 7

---

## Context

### Original Request

Full review of `pykoclaw/src/pykoclaw/` for simplification opportunities.
The codebase is already lean (~1,100 lines across 11 files). These are
the clear wins that don't risk regressions or plugin compatibility.

### Analysis Summary

| File            | Lines | Verdict                                           |
|-----------------|------:|---------------------------------------------------|
| `db.py`         |   415 | Dead `TaskRunLog` import; `error` param silently discarded in `mark_delivery_failed` |
| `tools.py`      |   186 | Response-dict boilerplate → helper                |
| `scheduler.py`  |    95 | Duplicated `next_run` computation in two branches |
| `agent_core.py` |    94 | Buffered generator deserves a docstring note       |
| `models.py`     |    45 | `TaskRunLog` model never instantiated             |
| `__init__.py`   |     1 | Orphan `__version__` duplicates `pyproject.toml`, never imported |
| `plugins.py`    |    73 | Clean — no changes                                |
| `sdk_consume.py` |   60 | Clean — no changes                                |
| `__main__.py`   |    81 | Clean — no changes                                |
| `config.py`     |    26 | Clean — no changes                                |
| `scheduling.py` |    26 | Clean — no changes                                |

### Verification Tools Used

- `ruff check --select F401` (unused imports) → found `TaskRunLog`
- `ruff check --select ARG` (unused arguments) → found `error` param in `mark_delivery_failed`
- `vulture --min-confidence 60` (dead code) → confirmed the above, no other true positives
- Manual cross-repo `rg` for every public symbol → confirmed `__version__` never imported

### Key Constraint

`TaskRunLog` must be confirmed dead before removal. Verification:

- `db.py` imports it but never uses it (no function returns `TaskRunLog`
  instances; `log_task_run()` is insert-only)
- No other file in any package imports or references `TaskRunLog`
- The `task_run_logs` **table** stays — only the Pydantic model is removed.
  If a future feature needs to read run logs, it can re-add the model then.

---

## Work Objectives

### Core Objective

Reduce visual noise and remove dead code in the core package without
changing behaviour, public APIs, or plugin compatibility.

### Definition of Done

- [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass, 0 failures
- [ ] All 7 commits land on the feature branch
- [ ] No plugin import paths change
- [ ] `rg "TaskRunLog" pykoclaw/src/ pykoclaw-*/src/` → no hits
- [ ] `rg "__version__" pykoclaw/src/pykoclaw/__init__.py` → no hits
- [ ] `ruff check pykoclaw/src/pykoclaw/ --select F401,ARG` → no errors

### Must NOT Do (Guardrails)

- **MUST NOT** change public function signatures (parameters, return types),
  except `mark_delivery_failed` where fixing the silently-discarded `error`
  param is a bug fix, not a signature change
- **MUST NOT** delete the `task_run_logs` DB table or its schema
- **MUST NOT** change `query_agent()` from `AsyncGenerator` to `list` (would
  break all callers)
- **MUST NOT** remove `log_task_run()` — it is called from `scheduler.py`
- **MUST NOT** change plugin Protocol or Base class
- **MUST NOT** remove `dedent()` from multi-line strings (project convention)

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**

### Test Decision
- **Infrastructure exists**: YES
- **Automated tests**: YES (tests-only — no new tests needed; all changes are
  refactors that existing tests already cover)
- **Framework**: pytest
- **Gate command**: `uv run pytest pykoclaw/tests/ --tb=short -q`

---

## TODOs

- [ ] 1. Add `_text_response()` helper to `tools.py`

  **What to do**:
  - Add a private helper at module level:
    ```python
    def _text_response(text: str) -> dict[str, Any]:
        return {"content": [{"type": "text", "text": text}]}
    ```
  - Replace all 5 occurrences of the
    `{"content": [{"type": "text", "text": ...}]}` dict literal in
    `schedule_task`, `list_tasks`, `pause_task`, `resume_task`, and
    `cancel_task` with calls to `_text_response(...)`.

  **Must NOT do**:
  - Do not change any tool names, descriptions, or schemas
  - Do not change tool logic

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None
  - **Blocked By**: None

  **References**:
  - `pykoclaw/src/pykoclaw/tools.py` — all 5 tool handlers

  **Acceptance Criteria**:
  - [ ] `_text_response` function exists in `tools.py`
  - [ ] No inline `{"content": [{"type": "text", ...}]}` dicts remain in tool handlers
  - [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: tools module imports and MCP server creates successfully
    Tool: Bash
    Steps:
      1. Run: uv run python -c "from pykoclaw.tools import make_mcp_server; print('OK')"
      2. Assert: prints "OK"
      3. Run: uv run pytest pykoclaw/tests/ --tb=short -q
      4. Assert: exit code 0
    Expected Result: Helper works, no regressions
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `refactor(tools): extract _text_response helper to reduce boilerplate`
  - Files: `pykoclaw/src/pykoclaw/tools.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ --tb=short -q`

---

- [ ] 2. De-duplicate `next_run` computation in `scheduler.py`

  **What to do**:
  - In `run_task()`, the following block appears identically in both the
    success path (after `async for`) and the `except` path:
    ```python
    if task.schedule_type in ("cron", "interval"):
        next_run = compute_next_run(task.schedule_type, task.schedule_value)
    else:
        next_run = None
    ```
  - Move it to a single computation **after** the try/except, in a
    `finally`-adjacent position. Both branches need `next_run` so compute
    it once before the shared `update_task_after_run` / `log_task_run`
    calls.
  - Restructure the function to:
    1. Run the agent query inside try/except, capturing `result_text` and
       `error_msg`.
    2. After the try/except, compute `next_run` once.
    3. Then do `update_task_after_run`, `log_task_run`, `enqueue_delivery`.

  **Must NOT do**:
  - Do not change the scheduler loop or polling interval
  - Do not change error handling semantics (recurring tasks must still get
    `next_run` on error — this was fixed in the prior code-review plan)
  - Do not change `result_summary` truncation logic

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:
  - `pykoclaw/src/pykoclaw/scheduler.py:19-82` — `run_task()` function
  - `pykoclaw/src/pykoclaw/scheduling.py` — `compute_next_run()`

  **Acceptance Criteria**:
  - [ ] `compute_next_run` is called exactly once in `run_task()` (not twice)
  - [ ] Recurring tasks still get `next_run` on both success and error
  - [ ] One-time tasks still get `next_run = None` on both success and error
  - [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: compute_next_run called exactly once
    Tool: Bash
    Steps:
      1. Run: rg -c "compute_next_run" pykoclaw/src/pykoclaw/scheduler.py
      2. Assert: output is "1" (import line excluded — count only calls)
    Expected Result: Single call site
    Evidence: Terminal output

  Scenario: Tests still pass
    Tool: Bash
    Steps:
      1. Run: uv run pytest pykoclaw/tests/ --tb=short -q
      2. Assert: exit code 0
    Expected Result: No regressions
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `refactor(scheduler): de-duplicate next_run computation in run_task`
  - Files: `pykoclaw/src/pykoclaw/scheduler.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ --tb=short -q`

---

- [ ] 3. Remove unused `TaskRunLog` import from `db.py`

  **What to do**:
  - Remove `TaskRunLog` from the import line in `db.py`:
    ```python
    # Before:
    from pykoclaw.models import Conversation, DeliveryQueueItem, ScheduledTask, TaskRunLog
    # After:
    from pykoclaw.models import Conversation, DeliveryQueueItem, ScheduledTask
    ```

  **Must NOT do**:
  - Do not remove `TaskRunLog` from `models.py` yet (that's Task 4)
  - Do not touch any other imports

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: Task 4
  - **Blocked By**: Task 2

  **References**:
  - `pykoclaw/src/pykoclaw/db.py:14` — the import line

  **Acceptance Criteria**:
  - [ ] `TaskRunLog` does not appear in `db.py`
  - [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: No TaskRunLog reference in db.py
    Tool: Bash
    Steps:
      1. Run: rg "TaskRunLog" pykoclaw/src/pykoclaw/db.py
      2. Assert: no output
      3. Run: uv run pytest pykoclaw/tests/ --tb=short -q
      4. Assert: exit code 0
    Expected Result: Dead import removed cleanly
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `refactor(db): remove unused TaskRunLog import`
  - Files: `pykoclaw/src/pykoclaw/db.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ --tb=short -q`

---

- [ ] 4. Remove dead `TaskRunLog` model from `models.py`

  **What to do**:
  - First, verify no code anywhere instantiates or imports `TaskRunLog`:
    ```bash
    rg "TaskRunLog" pykoclaw/src/ pykoclaw-*/src/
    ```
    After Task 3, the only hit should be the class definition in `models.py`.
  - Delete the `TaskRunLog` class (8 lines) from `models.py`.
  - The `task_run_logs` **table** and `log_task_run()` function stay — they
    use raw SQL, not the model.

  **Must NOT do**:
  - Do not remove the `task_run_logs` table from the schema
  - Do not remove `log_task_run()` from `db.py`
  - Do not remove `TaskRunLog` if any consumer is found during verification

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None
  - **Blocked By**: Task 3

  **References**:
  - `pykoclaw/src/pykoclaw/models.py:28-35` — `TaskRunLog` class to remove
  - `pykoclaw/src/pykoclaw/db.py` — `log_task_run()` inserts directly via SQL

  **Acceptance Criteria**:
  - [ ] `rg "TaskRunLog" pykoclaw/src/ pykoclaw-*/src/` → no hits
  - [ ] `task_run_logs` table schema unchanged in `db.py`
  - [ ] `log_task_run()` function unchanged in `db.py`
  - [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: TaskRunLog fully removed
    Tool: Bash
    Steps:
      1. Run: rg "TaskRunLog" pykoclaw/src/ pykoclaw-*/src/ 2>/dev/null
      2. Assert: no output (or exit code 1)
      3. Run: rg "log_task_run" pykoclaw/src/pykoclaw/db.py
      4. Assert: function still exists
      5. Run: uv run pytest pykoclaw/tests/ --tb=short -q
      6. Assert: exit code 0
    Expected Result: Dead model removed, insert function preserved
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `refactor(models): remove dead TaskRunLog model (table + insert preserved)`
  - Files: `pykoclaw/src/pykoclaw/models.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ --tb=short -q`

---

- [ ] 5. Fix `mark_delivery_failed` silently discarding `error` parameter

  **What to do**:
  - `mark_delivery_failed()` in `db.py` accepts an `error: str` parameter but
    the SQL `UPDATE` never stores it. The `delivery_queue` table has no
    `error` column, so two things are needed:
    1. Add an `ALTER TABLE delivery_queue ADD COLUMN error TEXT` migration
       in `init_db()` (same `_add_column` pattern used for `scheduled_tasks`).
    2. Update the `UPDATE` SQL in `mark_delivery_failed` to also set
       `error = ?` and bind the parameter.
    3. Add `error: str | None = None` field to the `DeliveryQueueItem` model.

  **Must NOT do**:
  - Do not change the function signature (callers already pass `error`)
  - Do not change `mark_delivered` or `enqueue_delivery`
  - Do not backfill existing rows

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None
  - **Blocked By**: Task 4

  **References**:
  - `pykoclaw/src/pykoclaw/db.py:249-254` — `mark_delivery_failed()` function
  - `pykoclaw/src/pykoclaw/db.py:109-114` — `_add_column` migration pattern
  - `pykoclaw/src/pykoclaw/models.py` — `DeliveryQueueItem`
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py` — caller
  - `pykoclaw-acp/src/pykoclaw_acp/server.py` — caller

  **Acceptance Criteria**:
  - [ ] `mark_delivery_failed` SQL includes `error = ?`
  - [ ] `init_db` adds `error TEXT` column to `delivery_queue` via `_add_column`
  - [ ] `DeliveryQueueItem` model has `error: str | None = None` field
  - [ ] `ruff check pykoclaw/src/pykoclaw/ --select ARG` → no errors (on core)
  - [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: error is stored in the database
    Tool: Bash
    Steps:
      1. Run: uv run python -c "
         from pykoclaw.db import init_db, enqueue_delivery, mark_delivery_failed
         from pathlib import Path
         import tempfile, os
         with tempfile.TemporaryDirectory() as d:
             db = init_db(Path(d) / 'test.db')
             enqueue_delivery(db, task_id='t1', task_run_log_id=None,
                 conversation='test', channel_prefix='test', message='hi')
             row = db.execute('SELECT id FROM delivery_queue').fetchone()
             mark_delivery_failed(db, row['id'], 'send failed')
             row2 = db.execute('SELECT error FROM delivery_queue WHERE id=?', (row['id'],)).fetchone()
             assert row2['error'] == 'send failed', f'got {row2[\"error\"]}'
             print('OK')
         "
      2. Assert: prints "OK"
    Expected Result: error string persisted to DB
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `fix(db): store error string in mark_delivery_failed instead of discarding it`
  - Files: `pykoclaw/src/pykoclaw/db.py`, `pykoclaw/src/pykoclaw/models.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ --tb=short -q`

---

- [ ] 6. Remove orphan `__version__` from `__init__.py`

  **What to do**:
  - Delete the single line `__version__ = "0.1.0"` from
    `pykoclaw/src/pykoclaw/__init__.py`.
  - This value duplicates `pyproject.toml`'s `version = "0.1.0"` and is
    never imported or referenced by any code in any package.
  - The file becomes empty, which is fine for a namespace package.

  **Must NOT do**:
  - Do not delete the `__init__.py` file itself
  - Do not add `importlib.metadata.version()` as replacement (no consumer
    needs it — add that when/if a consumer appears)

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None
  - **Blocked By**: Task 5

  **References**:
  - `pykoclaw/src/pykoclaw/__init__.py` — the 1-line file
  - `pykoclaw/pyproject.toml` — canonical version source

  **Acceptance Criteria**:
  - [ ] `rg "__version__" pykoclaw/src/pykoclaw/__init__.py` → no hits
  - [ ] `uv run python -c "import pykoclaw; print('OK')"` → prints "OK"
  - [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Package still importable after removing __version__
    Tool: Bash
    Steps:
      1. Run: uv run python -c "import pykoclaw; print(dir(pykoclaw))"
      2. Assert: no error; __version__ not in output
      3. Run: uv run pytest pykoclaw/tests/ --tb=short -q
      4. Assert: exit code 0
    Expected Result: Clean import, no regressions
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `refactor: remove orphan __version__ (duplicates pyproject.toml, never imported)`
  - Files: `pykoclaw/src/pykoclaw/__init__.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ --tb=short -q`

---

- [ ] 7. Document buffered-generator behaviour in `agent_core.py`

  **What to do**:
  - Add a note to the `query_agent()` docstring explaining that the current
    implementation buffers all messages before yielding (i.e. it is not a
    true streaming generator). This prevents future developers from
    assuming per-message streaming.
  - Suggested addition to the docstring:
    ```
    Note: Messages are currently buffered — all SDK messages are collected
    before any are yielded. To add true per-message streaming, the
    callback/collect/yield pattern would need to be replaced with an
    async queue or similar mechanism.
    ```

  **Must NOT do**:
  - Do not change any code logic
  - Do not change the return type from `AsyncGenerator` to `list`
  - Do not restructure the function

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None
  - **Blocked By**: Task 4

  **References**:
  - `pykoclaw/src/pykoclaw/agent_core.py:54-94` — `query_agent()` function

  **Acceptance Criteria**:
  - [ ] `query_agent()` docstring mentions buffered behaviour
  - [ ] No code changes beyond the docstring
  - [ ] `uv run pytest pykoclaw/tests/ --tb=short -q` → all pass

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Docstring updated
    Tool: Bash
    Steps:
      1. Run: rg "buffered" pykoclaw/src/pykoclaw/agent_core.py
      2. Assert: at least one hit in the docstring
      3. Run: uv run pytest pykoclaw/tests/ --tb=short -q
      4. Assert: exit code 0
    Expected Result: Documentation-only change, no regressions
    Evidence: Terminal output
  ```

  **Commit**: YES
  - Message: `docs(agent_core): document buffered-generator behaviour in query_agent`
  - Files: `pykoclaw/src/pykoclaw/agent_core.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/ --tb=short -q`

---

## Commit Strategy

| Task | Message | Files | Gate |
|------|---------|-------|------|
| 1 | `refactor(tools): extract _text_response helper to reduce boilerplate` | `tools.py` | pytest |
| 2 | `refactor(scheduler): de-duplicate next_run computation in run_task` | `scheduler.py` | pytest |
| 3 | `refactor(db): remove unused TaskRunLog import` | `db.py` | pytest |
| 4 | `refactor(models): remove dead TaskRunLog model (table + insert preserved)` | `models.py` | pytest |
| 5 | `fix(db): store error string in mark_delivery_failed instead of discarding it` | `db.py`, `models.py` | pytest |
| 6 | `refactor: remove orphan __version__ (duplicates pyproject.toml, never imported)` | `__init__.py` | pytest |
| 7 | `docs(agent_core): document buffered-generator behaviour in query_agent` | `agent_core.py` | pytest |

---

## Success Criteria

### Verification Commands
```bash
uv run pytest pykoclaw/tests/ --tb=short -q
# Expected: all pass, 0 failures (same count as baseline)

rg "TaskRunLog" pykoclaw/src/ pykoclaw-*/src/
# Expected: no hits

rg "__version__" pykoclaw/src/pykoclaw/__init__.py
# Expected: no hits

rg "_text_response" pykoclaw/src/pykoclaw/tools.py
# Expected: 1 def + 5+ call sites

rg -c "compute_next_run" pykoclaw/src/pykoclaw/scheduler.py
# Expected: 2 (1 import + 1 call)

uvx ruff check pykoclaw/src/pykoclaw/ --select F401,ARG
# Expected: All checks passed!
```

### Final Checklist
- [ ] All 7 tasks completed
- [ ] All tests pass
- [ ] No public API changes (except bug fix in task 5)
- [ ] No plugin compatibility changes
- [ ] DB schema: only additive migration (new `error` column on `delivery_queue`)
- [ ] ~40 lines net reduction
