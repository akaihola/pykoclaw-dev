# Scheduled Task Delivery & Channel Routing

## Status: Done

## Completed: 2026-02-16

## TL;DR

> **Quick Summary**: Make scheduled tasks deliver their results back to the user via the originating channel (WhatsApp, ACP, Chat) using a DB-based delivery queue that decouples the scheduler from channel plugins. Each channel plugin polls for pending deliveries and sends them through its native transport.
>
> **Deliverables**:
>
> - `delivery_queue` DB table and CRUD functions
> - Scheduler writes results to queue after task execution
> - WhatsApp delivery polling loop using `OutgoingQueue.send()`
> - ACP delivery polling loop using `session/update` notifications (best-effort)
> - Optional `target_conversation` parameter on `schedule_task` tool
> - Improved CLI help text for `scheduler` and `tasks` commands
> - Tests for the full scheduler→queue→delivery flow
>
> **Estimated Effort**: Medium-Large
> **Parallel Execution**: YES — 2 waves
> **Critical Path**: Task 1 → Tasks 2,3 parallel → Tasks 4,5 parallel → Task 6 → Task 7

---

## Context

### Original Request

User wants scheduled task results delivered back to them through the channel they originated from (WhatsApp, ACP via Mitto, Chat). Current state: scheduler runs tasks and prints results to stdout — results are never sent to any channel. Additionally, user wants cross-channel targeting ("send results to Telegram" while on ACP) and semantic matching ("the channel where we talked about lunch"), but these are deferred to later phases.

### Interview Summary

**Key Discussions**:

- User's primary channel is ACP via Mitto; will experiment with Telegram in future
- Default: deliver results to originating channel
- Fallback: if originating channel is inactive, route to latest active channel (Phase 2)
- Cross-channel explicit targeting via `target_conversation` parameter (Phase 1 — tool parameter only)
- Semantic matching — "the channel where we talked about X" (Phase 3)
- CLI help text for `scheduler` and `tasks` commands is confusing and needs fixing

**Research Findings**:

- Scheduler (`scheduler.py`) calls `query_agent()` directly — result only goes to `print()` and DB
- `dispatch_to_agent()` in pykoclaw-messaging has `on_text` callback — this is how channels deliver in real-time, but the scheduler doesn't use it
- Channel plugins run as **separate processes** sharing only SQLite — scheduler can't call WhatsApp's `send()` directly
- WhatsApp's MCP `send_message` tool only inserts into `wa_messages` table — it does NOT actually transmit via Neonize. Real send path: `OutgoingQueue.send()` → `client.send_message()`
- ACP sessions are ephemeral — server only lives while client is connected via stdio
- Conversation names encode channel: `wa-<jid>`, `acp-<session_id[:8]>`, but chat conversations have no prefix

### Metis Review

**Identified Gaps** (addressed):

- WhatsApp `send_message` MCP tool doesn't actually send — delivery must use `OutgoingQueue.send()` directly
- ACP has no unsolicited push path — delivery is best-effort while client is connected
- Conversation name parsing is fragile for chat (no prefix) — store channel prefix explicitly on delivery queue rows
- Scope creep risk — phased aggressively into 3 phases; this plan is Phase 1 only
- Protocol modification risk — DO NOT modify `PykoClawPlugin` protocol; channels opt-in by running a poller
- SQLite contention — must set WAL mode in scheduler (WhatsApp already does this)
- Heartbeat table premature — deferred to Phase 2 (fallback routing)

---

## Work Objectives

### Core Objective

Enable the scheduler to deliver task results back to the user's originating channel via a DB-based delivery queue, with each channel plugin autonomously polling and delivering messages through its native transport.

### Concrete Deliverables

- New `delivery_queue` table in `pykoclaw.db`
- New `DeliveryQueueItem` model in `pykoclaw/models.py`
- CRUD functions for delivery queue in `pykoclaw/db.py`
- Modified `run_task()` in `scheduler.py` to enqueue deliveries
- WAL mode set in scheduler process
- WhatsApp delivery polling loop in `pykoclaw-whatsapp`
- ACP delivery polling loop in `pykoclaw-acp`
- `target_conversation` parameter on `schedule_task` MCP tool
- Improved CLI help text
- Integration tests for the delivery flow

### Definition of Done

- [x] Scheduling a task on WhatsApp results in delivery back to that WhatsApp chat when the task runs
- [x] Scheduling a task on ACP results in delivery back to that ACP session (if connected)
- [x] Explicit `target_conversation` override is accepted by `schedule_task` tool
- [x] `uv run pytest` passes across all affected packages (162 passed, 4 pre-existing ACP failures)
- [x] CLI help text accurately describes what `scheduler` and `tasks` commands do

### Must Have

- DB-based delivery queue (the core IPC mechanism)
- Scheduler → queue write after each task execution
- WhatsApp delivery polling loop using `OutgoingQueue.send()`
- ACP delivery polling loop (best-effort while connected)
- WAL mode in scheduler
- Tests for delivery queue CRUD and scheduler integration

### Must NOT Have (Guardrails)

- DO NOT modify the `PykoClawPlugin` protocol — channels opt-in to delivery by running a poller
- DO NOT implement semantic matching (`find_conversation` tool) — Phase 3
- DO NOT implement fallback routing (heartbeat + "try next active channel") — Phase 2
- DO NOT implement heartbeat table — Phase 2
- DO NOT add retry/backoff logic for failed deliveries — keep simple for Phase 1
- DO NOT use WhatsApp's MCP `send_message` tool for delivery — it only inserts into DB, doesn't transmit
- DO NOT require a running WhatsApp or ACP client for tests — all verification via DB assertions and mocks
- DO NOT over-engineer the delivery queue — no priority, no TTL, no dead letter queue in Phase 1

---

## Verification Strategy (MANDATORY)

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks in this plan MUST be verifiable WITHOUT any human action.
> ALL verification is executed by the agent using tools. No exceptions.

### Test Decision

- **Infrastructure exists**: YES
- **Automated tests**: YES (tests-after)
- **Framework**: pytest + pytest-asyncio

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

Every task includes QA scenarios using Bash (pytest, CLI commands) as the primary verification tool.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
└── Task 1: Delivery queue infrastructure (DB + models + CRUD)

Wave 2 (After Wave 1):
├── Task 2: Scheduler integration (write results to queue)
├── Task 3: schedule_task tool target_conversation parameter
└── Task 7: CLI help text improvements

Wave 3 (After Wave 2):
├── Task 4: WhatsApp delivery polling loop
└── Task 5: ACP delivery polling loop

Wave 4 (After Wave 3):
└── Task 6: Integration tests for full delivery flow

Wave 5 (After Wave 4):
└── Task 8: Create feature branches, commit all changes
```

### Dependency Matrix

| Task | Depends On    | Blocks        | Can Parallelize With |
| ---- | ------------- | ------------- | -------------------- |
| 1    | None          | 2, 3, 4, 5, 6 | None (foundation)    |
| 2    | 1             | 4, 5, 6       | 3, 7                 |
| 3    | 1             | 6             | 2, 7                 |
| 4    | 1, 2          | 6             | 5                    |
| 5    | 1, 2          | 6             | 4                    |
| 6    | 1, 2, 3, 4, 5 | 8             | None (integration)   |
| 7    | None          | 8             | 2, 3                 |
| 8    | All           | None          | None (final)         |

### Agent Dispatch Summary

| Wave | Tasks   | Recommended Agents                                 |
| ---- | ------- | -------------------------------------------------- |
| 1    | 1       | task(category="unspecified-high")                  |
| 2    | 2, 3, 7 | dispatch parallel                                  |
| 3    | 4, 5    | dispatch parallel                                  |
| 4    | 6       | task(category="unspecified-high")                  |
| 5    | 8       | task(category="quick", load_skills=["git-master"]) |

---

## Multi-Repo Branch Strategy

Each subdirectory is a separate git repo. Create `feat/delivery-queue` branches in:

- `pykoclaw/` — core changes (Tasks 1, 2, 3, 6, 7)
- `pykoclaw-whatsapp/` — delivery polling (Task 4)
- `pykoclaw-acp/` — delivery polling (Task 5)

Commit frequently within each repo. The workspace root repo (`pykoclaw-dev`) does not need changes.

---

## TODOs

- [x]   1. Delivery queue infrastructure — DB table, model, CRUD

    **What to do**:
    - Add `DeliveryQueueItem` Pydantic model to `pykoclaw/src/pykoclaw/models.py`
        ```python
        class DeliveryQueueItem(BaseModel):
            id: str
            task_id: str
            task_run_log_id: int | None
            conversation: str      # target conversation name (e.g., "wa-123@s.whatsapp.net")
            channel_prefix: str    # parsed prefix (e.g., "wa", "acp", "chat")
            message: str           # the result text to deliver
            status: str            # "pending", "delivered", "failed"
            created_at: str        # ISO 8601
            delivered_at: str | None
        ```
    - Add `delivery_queue` table creation to `init_db()` in `pykoclaw/src/pykoclaw/db.py`:
        ```sql
        CREATE TABLE IF NOT EXISTS delivery_queue (
            id TEXT PRIMARY KEY,
            task_id TEXT NOT NULL,
            task_run_log_id INTEGER,
            conversation TEXT NOT NULL,
            channel_prefix TEXT NOT NULL,
            message TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            created_at TEXT NOT NULL,
            delivered_at TEXT,
            FOREIGN KEY (task_id) REFERENCES scheduled_tasks(id)
        );
        CREATE INDEX IF NOT EXISTS idx_delivery_queue_status
            ON delivery_queue(channel_prefix, status);
        ```
    - Add CRUD functions to `db.py`:
        - `enqueue_delivery(db, task_id, task_run_log_id, conversation, channel_prefix, message) -> str` — creates row, returns id
        - `get_pending_deliveries(db, channel_prefix) -> list[DeliveryQueueItem]` — SELECT WHERE status='pending' AND channel_prefix=?
        - `mark_delivered(db, delivery_id) -> None` — UPDATE status='delivered', delivered_at=now
        - `mark_delivery_failed(db, delivery_id, error: str) -> None` — UPDATE status='failed'
    - Add a helper function `parse_channel_prefix(conversation_name: str) -> str` — extracts prefix before first `-`, defaults to `"chat"` if no dash found

    **Must NOT do**:
    - Do NOT add TTL, retry count, priority, or dead letter queue — keep simple
    - Do NOT modify the existing `scheduled_tasks` or `task_run_logs` tables

    **Recommended Agent Profile**:
    - **Category**: `unspecified-high`
        - Reason: Core DB infrastructure with Pydantic models; important foundational work
    - **Skills**: []
        - No special skills needed — standard Python/SQLite
    - **Skills Evaluated but Omitted**:
        - `git-master`: Not needed yet — committing is a separate task

    **Parallelization**:
    - **Can Run In Parallel**: NO (foundation task)
    - **Parallel Group**: Wave 1 (alone)
    - **Blocks**: Tasks 2, 3, 4, 5, 6
    - **Blocked By**: None

    **References**:

    **Pattern References** (existing code to follow):
    - `pykoclaw/src/pykoclaw/models.py` — existing `ScheduledTask` and `TaskRunLog` Pydantic models; follow exact same pattern (frozen `BaseModel`, `str` fields for timestamps)
    - `pykoclaw/src/pykoclaw/db.py:init_db()` — where existing tables (`conversations`, `scheduled_tasks`, `task_run_logs`) are created; add new table here
    - `pykoclaw/src/pykoclaw/db.py:create_task()` — pattern for INSERT functions; follow same style with explicit parameter names
    - `pykoclaw/src/pykoclaw/db.py:get_due_tasks()` — pattern for SELECT functions returning model lists; follow same row→model mapping

    **API/Type References**:
    - `pykoclaw/src/pykoclaw/models.py:ScheduledTask` — field naming convention to match
    - `pykoclaw/src/pykoclaw/db.py:DbConnection` type alias — use this for all db parameters

    **Test References**:
    - `pykoclaw/tests/test_db.py` — test patterns for DB CRUD; follow fixture style

    **Acceptance Criteria**:
    - [x] `DeliveryQueueItem` model defined in `models.py` with all fields
    - [x] `delivery_queue` table created by `init_db()`
    - [x] `enqueue_delivery()` inserts row and returns delivery ID
    - [x] `get_pending_deliveries("wa")` returns only pending rows for that prefix
    - [x] `mark_delivered()` updates status and sets `delivered_at`
    - [x] `parse_channel_prefix("wa-123@s.whatsapp.net")` returns `"wa"`
    - [x] `parse_channel_prefix("myproject")` returns `"chat"` (no dash → default)
    - [x] `uv run pytest pykoclaw/tests/test_db.py` passes (4 delivery tests pass)

    **Agent-Executed QA Scenarios:**

    ```
    Scenario: Delivery queue CRUD round-trip
      Tool: Bash (pytest)
      Preconditions: None
      Steps:
        1. uv run pytest pykoclaw/tests/test_db.py -v -k "delivery"
        2. Assert: All delivery-related tests pass
      Expected Result: 0 failures
      Evidence: pytest output captured

    Scenario: parse_channel_prefix handles all cases
      Tool: Bash (python)
      Preconditions: None
      Steps:
        1. uv run python -c "from pykoclaw.db import parse_channel_prefix; assert parse_channel_prefix('wa-123') == 'wa'; assert parse_channel_prefix('acp-abc') == 'acp'; assert parse_channel_prefix('myproject') == 'chat'; print('OK')"
        2. Assert: "OK" printed
      Expected Result: All assertions pass
      Evidence: stdout captured
    ```

    **Commit**: YES
    - Message: `feat(db): add delivery_queue table and CRUD for scheduled task result routing`
    - Files: `src/pykoclaw/db.py`, `src/pykoclaw/models.py`, `tests/test_db.py`
    - Pre-commit: `uv run pytest pykoclaw/tests/test_db.py`

---

- [x]   2. Scheduler integration — write results to delivery queue

    **What to do**:
    - Modify `run_task()` in `pykoclaw/src/pykoclaw/scheduler.py`:
        - After `log_task_run()` (line ~62-69), call `enqueue_delivery()` to write the result to the delivery queue
        - Parse channel prefix from `task.conversation` using `parse_channel_prefix()`
        - If the task has a `target_conversation` set (see Task 3), use that instead of `task.conversation`
        - Only enqueue if there's actual result text (skip empty results and errors for now)
    - Set WAL mode in `run_scheduler()`:
        - Add `db.execute("PRAGMA journal_mode=WAL")` at the start of `run_scheduler()` (before the `while True` loop)
        - WhatsApp already does this at `pykoclaw-whatsapp/__init__.py:42`, so this makes the scheduler consistent
    - Import `enqueue_delivery` and `parse_channel_prefix` from `db.py`

    **Must NOT do**:
    - Do NOT change the `query_agent()` call or its parameters
    - Do NOT remove the `print()` statement — keep stdout logging alongside queue writes
    - Do NOT add retry logic for failed enqueues

    **Recommended Agent Profile**:
    - **Category**: `quick`
        - Reason: Small, focused change to one function in one file
    - **Skills**: []

    **Parallelization**:
    - **Can Run In Parallel**: YES
    - **Parallel Group**: Wave 2 (with Tasks 3, 7)
    - **Blocks**: Tasks 4, 5, 6
    - **Blocked By**: Task 1

    **References**:

    **Pattern References**:
    - `pykoclaw/src/pykoclaw/scheduler.py:18-70` — the `run_task()` function to modify; enqueue after line 69 (`log_task_run()`)
    - `pykoclaw/src/pykoclaw/scheduler.py:73-81` — `run_scheduler()` where WAL pragma should be added (after line 73, before the `while True`)
    - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py:42` — example of WAL pragma setting

    **API/Type References**:
    - `pykoclaw/src/pykoclaw/db.py:enqueue_delivery()` — the function created in Task 1
    - `pykoclaw/src/pykoclaw/db.py:parse_channel_prefix()` — the helper created in Task 1

    **Test References**:
    - `pykoclaw/tests/test_scheduler.py` — existing scheduler tests that mock `query_agent`; follow same pattern

    **Acceptance Criteria**:
    - [x] After `run_task()` completes, a row exists in `delivery_queue` with `status='pending'`
    - [x] The `channel_prefix` in the delivery row matches the task's conversation prefix
    - [x] If task result is empty, no delivery row is created
    - [x] WAL mode is set in `run_scheduler()` before the polling loop (`scheduler.py:87`)
    - [x] `uv run pytest pykoclaw/tests/test_scheduler.py` passes

    **Agent-Executed QA Scenarios:**

    ```
    Scenario: Scheduler enqueues delivery after successful task run
      Tool: Bash (pytest)
      Preconditions: Task 1 completed
      Steps:
        1. uv run pytest pykoclaw/tests/test_scheduler.py -v -k "delivery"
        2. Assert: Tests verify delivery_queue row exists after run_task()
      Expected Result: 0 failures
      Evidence: pytest output

    Scenario: WAL mode is set
      Tool: Bash (grep)
      Preconditions: None
      Steps:
        1. grep -n "journal_mode=WAL" pykoclaw/src/pykoclaw/scheduler.py
        2. Assert: Match found in run_scheduler()
      Expected Result: Line with PRAGMA statement found
      Evidence: grep output
    ```

    **Commit**: YES
    - Message: `feat(scheduler): enqueue delivery after task execution`
    - Files: `src/pykoclaw/scheduler.py`, `tests/test_scheduler.py`
    - Pre-commit: `uv run pytest pykoclaw/tests/test_scheduler.py`

---

- [x]   3. Add `target_conversation` parameter to `schedule_task` tool

    **What to do**:
    - Modify the `schedule_task` tool in `pykoclaw/src/pykoclaw/tools.py`:
        - Add optional `target_conversation` parameter (str, default None)
        - Update the tool description to explain cross-channel targeting
        - Pass `target_conversation` to `create_task()` for storage
    - Add `target_conversation` column to `scheduled_tasks` table in `db.py`:
        - `ALTER TABLE scheduled_tasks ADD COLUMN target_conversation TEXT` (nullable)
        - Or add to the `CREATE TABLE IF NOT EXISTS` statement (since we're early and can recreate)
    - Add `target_conversation` field to `ScheduledTask` model in `models.py`
    - Modify `create_task()` in `db.py` to accept and store `target_conversation`
    - The scheduler (Task 2) reads `task.target_conversation` and uses it as the delivery target if set, otherwise falls back to `task.conversation`

    **Must NOT do**:
    - Do NOT implement conversation search/discovery — just accept an explicit name
    - Do NOT validate that the target conversation exists — the agent provides it

    **Recommended Agent Profile**:
    - **Category**: `quick`
        - Reason: Adding a parameter to an existing tool and a column to a table
    - **Skills**: []

    **Parallelization**:
    - **Can Run In Parallel**: YES
    - **Parallel Group**: Wave 2 (with Tasks 2, 7)
    - **Blocks**: Task 6
    - **Blocked By**: Task 1

    **References**:

    **Pattern References**:
    - `pykoclaw/src/pykoclaw/tools.py:19-55` — the `schedule_task` tool definition; add parameter here
    - `pykoclaw/src/pykoclaw/tools.py:31-46` — the `schedule_task` async function; modify args handling
    - `pykoclaw/src/pykoclaw/db.py:create_task()` — the INSERT function to modify

    **API/Type References**:
    - `pykoclaw/src/pykoclaw/models.py:ScheduledTask` — add `target_conversation: str | None` field
    - `pykoclaw/src/pykoclaw/db.py:create_task()` — add `target_conversation` parameter

    **Acceptance Criteria**:
    - [x] `schedule_task` tool accepts optional `target_conversation` parameter
    - [x] `ScheduledTask` model has `target_conversation` field (nullable) — `models.py:18`
    - [x] `create_task()` stores `target_conversation` in DB — `db.py:277`
    - [x] Tool description mentions cross-channel targeting capability — `tools.py:25`
    - [x] `uv run pytest pykoclaw/tests/` passes

    **Agent-Executed QA Scenarios:**

    ```
    Scenario: schedule_task tool accepts target_conversation
      Tool: Bash (pytest)
      Preconditions: Task 1 completed
      Steps:
        1. uv run pytest pykoclaw/tests/ -v -k "schedule"
        2. Assert: Tests pass including any new target_conversation tests
      Expected Result: 0 failures
      Evidence: pytest output
    ```

    **Commit**: YES (groups with Task 2)
    - Message: `feat(tools): add target_conversation parameter to schedule_task`
    - Files: `src/pykoclaw/tools.py`, `src/pykoclaw/db.py`, `src/pykoclaw/models.py`
    - Pre-commit: `uv run pytest pykoclaw/tests/`

---

- [x]   4. WhatsApp delivery polling loop

    **What to do**:
    - Add a delivery polling coroutine to the WhatsApp plugin that runs alongside the existing connection
    - Location: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py` (where the WhatsApp connection lifecycle lives)
    - The polling loop:
        1. Periodically (every 10s) calls `get_pending_deliveries(db, "wa")`
        2. For each pending delivery, extracts the channel ID from `delivery.conversation` (strip the `wa-` prefix)
        3. Builds a Neonize JID from the channel ID
        4. Calls `self._outgoing_queue.send(self._client, jid, delivery.message)`
        5. Calls `mark_delivered(db, delivery.id)`
        6. If send fails, calls `mark_delivery_failed(db, delivery.id, error)`
    - Follow the pattern of `ClientPool._sweep_loop()` in pykoclaw-acp for the async loop structure
    - Start the polling loop when the WhatsApp client connects (in the `connected` event handler)
    - Stop it on disconnect

    **Must NOT do**:
    - Do NOT use the MCP `send_message` tool — it only inserts into `wa_messages` and doesn't transmit
    - Do NOT modify `OutgoingQueue` — use its existing `send()` method
    - Do NOT add retry logic — if send fails, mark as failed and move on
    - Do NOT poll faster than every 10 seconds — SQLite contention risk

    **Recommended Agent Profile**:
    - **Category**: `unspecified-high`
        - Reason: Integrating async polling into existing WhatsApp connection lifecycle requires understanding the threading model
    - **Skills**: []

    **Parallelization**:
    - **Can Run In Parallel**: YES
    - **Parallel Group**: Wave 3 (with Task 5)
    - **Blocks**: Task 6
    - **Blocked By**: Tasks 1, 2

    **References**:

    **Pattern References**:
    - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:156-168` — `_sweep_loop()` pattern for async polling with `asyncio.create_task` and periodic `asyncio.sleep`
    - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:195-213` — the `_handle_agent_trigger()` method showing how `OutgoingQueue.send()` is called with client + JID + text
    - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:173-193` — JID building with `_build_jid()` method
    - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/queue.py` — `OutgoingQueue.send()` interface

    **API/Type References**:
    - `pykoclaw/src/pykoclaw/db.py:get_pending_deliveries()` — function created in Task 1
    - `pykoclaw/src/pykoclaw/db.py:mark_delivered()` — function created in Task 1
    - `pykoclaw/src/pykoclaw/db.py:mark_delivery_failed()` — function created in Task 1
    - `pykoclaw/src/pykoclaw/models.py:DeliveryQueueItem` — model created in Task 1

    **Documentation References**:
    - `CLAUDE.md:WhatsApp plugin uses 3 threads sharing one SQLite connection` — threading constraint to be aware of

    **WHY Each Reference Matters**:
    - The `_sweep_loop()` pattern shows exactly how to structure a background async poller
    - `_handle_agent_trigger()` shows the real WhatsApp send path via `OutgoingQueue.send()`
    - `_build_jid()` converts string JIDs to Neonize JID objects — needed for delivery
    - Threading model matters: the delivery poll likely runs on the asyncio thread, same as agent triggers

    **Acceptance Criteria**:
    - [x] Delivery polling coroutine exists and runs when WhatsApp is connected — `connection.py:240-268`
    - [x] Polling calls `get_pending_deliveries(db, "wa")` every ~10 seconds
    - [x] Pending deliveries are sent via `OutgoingQueue.send()` — `connection.py:264`
    - [x] Delivered items are marked via `mark_delivered()` — `connection.py:265`
    - [x] Failed sends are marked via `mark_delivery_failed()` — `connection.py:268`
    - [x] `uv run pytest pykoclaw-whatsapp/` passes (81 tests)

    **Agent-Executed QA Scenarios:**

    ```
    Scenario: WhatsApp delivery polling function exists and handles deliveries
      Tool: Bash (pytest or code inspection)
      Preconditions: Tasks 1, 2 completed
      Steps:
        1. uv run python -c "from pykoclaw_whatsapp.connection import WhatsAppConnection; print('import OK')"
        2. Assert: No import errors
        3. grep -n "get_pending_deliveries" pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py
        4. Assert: Function call found in delivery polling method
      Expected Result: Delivery polling code integrated
      Evidence: Import success + grep output

    Scenario: Delivery polling extracts correct JID from conversation name
      Tool: Bash (pytest)
      Preconditions: Test exists for JID extraction
      Steps:
        1. uv run pytest pykoclaw-whatsapp/ -v -k "delivery" (if test exists)
      Expected Result: JID correctly parsed from "wa-123@s.whatsapp.net" → "123@s.whatsapp.net"
      Evidence: pytest output
    ```

    **Commit**: YES
    - Message: `feat(whatsapp): add delivery queue polling for scheduled task results`
    - Files: `src/pykoclaw_whatsapp/connection.py`
    - Pre-commit: `uv run pytest pykoclaw-whatsapp/` (if tests exist)

---

- [x]   5. ACP delivery polling loop

    **What to do**:
    - Add a delivery polling coroutine to the ACP server that runs alongside the existing stdin reader
    - Location: `pykoclaw-acp/src/pykoclaw_acp/server.py` (or `client_pool.py` if delivery is per-session)
    - The polling loop:
        1. Periodically (every 10s) calls `get_pending_deliveries(db, "acp")`
        2. For each pending delivery, extracts the session ID from `delivery.conversation` (strip `acp-` prefix)
        3. Checks if a matching ACP session is still active in the client pool
        4. If active: sends a `session/update` notification with the result text
        5. Calls `mark_delivered(db, delivery.id)`
        6. If session not found (client disconnected): leave as pending (will deliver when client reconnects and creates new session, OR mark as failed after timeout — for Phase 1, just leave as pending)
    - Use `asyncio.create_task()` to start the poller alongside the existing event loop
    - Follow the `_sweep_loop()` pattern already in `client_pool.py`

    **Must NOT do**:
    - Do NOT block the stdin reader — polling must be a separate async task
    - Do NOT force-deliver to disconnected sessions — leave pending for Phase 1
    - Do NOT modify the ACP protocol — use existing `session/update` notification format

    **Recommended Agent Profile**:
    - **Category**: `unspecified-high`
        - Reason: ACP server architecture (stdio JSON-RPC) requires careful understanding of the event loop
    - **Skills**: []

    **Parallelization**:
    - **Can Run In Parallel**: YES
    - **Parallel Group**: Wave 3 (with Task 4)
    - **Blocks**: Task 6
    - **Blocked By**: Tasks 1, 2

    **References**:

    **Pattern References**:
    - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:156-168` — `_sweep_loop()` — exact pattern to follow for async polling
    - `pykoclaw-acp/src/pykoclaw_acp/server.py:146-158` — `_send_chunk()` — how to format and send `session/update` notifications
    - `pykoclaw-acp/src/pykoclaw_acp/server.py:55-62` — `_write()` method for writing JSON-RPC to stdout
    - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:127` — conversation naming: `f"acp-{session_id[:8]}"`

    **API/Type References**:
    - `pykoclaw/src/pykoclaw/db.py:get_pending_deliveries()` — function created in Task 1
    - `pykoclaw/src/pykoclaw/db.py:mark_delivered()` — function created in Task 1
    - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:ClientPool` — manages active sessions, can check if a session exists

    **WHY Each Reference Matters**:
    - `_sweep_loop()` is literally the same pattern we need — background async loop with periodic DB queries
    - `_send_chunk()` shows the exact JSON-RPC notification format for delivering text to ACP clients
    - `_write()` is the low-level stdout writer — delivery notification goes through here
    - Session ID truncation (`[:8]`) means we need to match delivery conversation `acp-<prefix>` to active sessions

    **Acceptance Criteria**:
    - [x] Delivery polling coroutine exists in ACP server — `server.py:190-238`
    - [x] Polling calls `get_pending_deliveries(db, "acp")` every ~10 seconds
    - [x] Active sessions receive `session/update` notifications with task results — `server.py:229`
    - [x] Delivered items are marked via `mark_delivered()` — `server.py:235`
    - [x] Inactive sessions: deliveries left as pending (not discarded) — `server.py:212`
    - [x] `uv run pytest pykoclaw-acp/` passes (23 passed, 4 pre-existing failures)

    **Agent-Executed QA Scenarios:**

    ```
    Scenario: ACP delivery polling function integrates with client pool
      Tool: Bash (code inspection)
      Preconditions: Tasks 1, 2 completed
      Steps:
        1. uv run python -c "from pykoclaw_acp.server import AcpServer; print('import OK')"
        2. Assert: No import errors
        3. grep -n "get_pending_deliveries" pykoclaw-acp/src/pykoclaw_acp/
        4. Assert: Function call found
      Expected Result: Delivery polling code integrated into ACP
      Evidence: Import success + grep output
    ```

    **Commit**: YES
    - Message: `feat(acp): add delivery queue polling for scheduled task results`
    - Files: `src/pykoclaw_acp/server.py` or `src/pykoclaw_acp/client_pool.py`
    - Pre-commit: `uv run pytest pykoclaw-acp/` (if tests exist)

---

- [x]   6. Integration tests for the full delivery flow

    **What to do**:
    - Create comprehensive tests covering the scheduler→queue→delivery pipeline
    - Location: `pykoclaw/tests/test_delivery.py` (new file)
    - Tests to write:
        1. **Scheduler enqueue test**: Create a task, mock `query_agent` to return text, run `run_task()`, verify `delivery_queue` row exists with `status='pending'`, correct `channel_prefix`, correct `message`
        2. **Empty result test**: Task with no output → no delivery row created
        3. **Error result test**: Task that raises → delivery row with error message OR no delivery (decide: should errors be delivered?)
        4. **Target conversation test**: Task with `target_conversation` set → delivery row uses target, not originating conversation
        5. **Channel prefix parsing edge cases**: Various conversation name formats
        6. **Delivery pickup test**: Create pending delivery, call `get_pending_deliveries()`, verify correct filtering by prefix
        7. **Mark delivered test**: Create delivery, mark delivered, verify `status='delivered'` and `delivered_at` set
    - Use the existing test patterns from `test_scheduler.py` — `tmp_path` fixtures, `patch("pykoclaw.scheduler.query_agent")`
    - All tests use in-memory or temp SQLite — no real channels needed

    **Must NOT do**:
    - Do NOT require running WhatsApp or ACP clients
    - Do NOT test actual message delivery to channels — only test the queue mechanics
    - Do NOT add flaky timing-dependent tests

    **Recommended Agent Profile**:
    - **Category**: `unspecified-high`
        - Reason: Integration tests spanning multiple modules require understanding the full flow
    - **Skills**: []

    **Parallelization**:
    - **Can Run In Parallel**: NO (depends on all previous tasks)
    - **Parallel Group**: Wave 4 (alone)
    - **Blocks**: Task 8
    - **Blocked By**: Tasks 1, 2, 3, 4, 5

    **References**:

    **Pattern References**:
    - `pykoclaw/tests/test_scheduler.py` — existing scheduler tests; follow exact same fixture and mocking patterns
    - `pykoclaw/tests/test_db.py` — existing DB tests; follow assertion patterns

    **Test References**:
    - `pykoclaw/tests/test_scheduler.py` — uses `patch("pykoclaw.scheduler.query_agent")` with async generator mock, `tmp_path` for DB
    - `pykoclaw/tests/test_db.py` — DB fixture patterns

    **Acceptance Criteria**:
    - [x] `test_delivery.py` exists with 8 test functions (≥5 required)
    - [x] Tests cover: enqueue (wa + acp), empty result skip, target conversation, prefix parsing, delivery pickup, mark delivered, error skip
    - [x] `uv run pytest pykoclaw/tests/test_delivery.py -v` → 8 passed
    - [x] `uv run pytest pykoclaw/tests/` → all tests pass (no regressions)

    **Agent-Executed QA Scenarios:**

    ```
    Scenario: All delivery integration tests pass
      Tool: Bash (pytest)
      Preconditions: Tasks 1-5 completed
      Steps:
        1. uv run pytest pykoclaw/tests/test_delivery.py -v
        2. Assert: All tests pass, 0 failures
        3. uv run pytest pykoclaw/tests/ -v
        4. Assert: No regressions in existing tests
      Expected Result: Full green test suite
      Evidence: pytest output captured
    ```

    **Commit**: YES
    - Message: `test(delivery): add integration tests for delivery queue flow`
    - Files: `tests/test_delivery.py`
    - Pre-commit: `uv run pytest pykoclaw/tests/`

---

- [x]   7. CLI help text improvements

    **What to do**:
    - Fix the `scheduler` command in `pykoclaw/src/pykoclaw/__main__.py`:
        - Change help from `"Manage scheduled tasks."` to `"Run the task scheduler daemon (polls every 60s for due tasks)."`
        - The command name is misleading — it doesn't "manage", it runs a long-lived polling loop
    - Fix the `tasks` command:
        - Change help from `"Manage tasks."` to `"List all scheduled tasks and their status."`
        - It's read-only — it doesn't let you manage anything
    - Improve the `tasks` command output format:
        - Add a header row: `ID | Conversation | Prompt | Status | Next Run`
        - Consider using `click.echo` with tabular formatting
    - Optionally add a `task-log` subcommand that shows recent `task_run_logs` entries for a given task ID

    **Must NOT do**:
    - Do NOT restructure the CLI — just improve descriptions and output
    - Do NOT add interactive task management (pause/resume from CLI) — that's a separate feature

    **Recommended Agent Profile**:
    - **Category**: `quick`
        - Reason: Small text changes and formatting improvements
    - **Skills**: []

    **Parallelization**:
    - **Can Run In Parallel**: YES
    - **Parallel Group**: Wave 2 (with Tasks 2, 3)
    - **Blocks**: Task 8
    - **Blocked By**: None

    **References**:

    **Pattern References**:
    - `pykoclaw/src/pykoclaw/__main__.py:38-69` — all CLI commands; modify help strings
    - `pykoclaw/src/pykoclaw/__main__.py:53-58` — `conversations` command output format (follow same style but add header)

    **API/Type References**:
    - `pykoclaw/src/pykoclaw/db.py:get_all_tasks()` — returns list of `ScheduledTask` used by `tasks` command
    - `pykoclaw/src/pykoclaw/db.py:get_task_run_logs()` — if it exists, use for `task-log` subcommand

    **Acceptance Criteria**:
    - [x] `uv run pykoclaw scheduler --help` → "Run the task scheduler daemon (polls every 60s for due tasks)."
    - [x] `uv run pykoclaw tasks --help` → "List all scheduled tasks and their status."
    - [x] `uv run pykoclaw tasks` output includes a header row
    - [x] Help text is accurate and non-misleading

    **Agent-Executed QA Scenarios:**

    ```
    Scenario: CLI help text is descriptive
      Tool: Bash
      Preconditions: None
      Steps:
        1. uv run pykoclaw --help
        2. Assert: "scheduler" entry does NOT say just "Manage scheduled tasks"
        3. Assert: "tasks" entry does NOT say just "Manage tasks"
        4. uv run pykoclaw scheduler --help
        5. Assert: Output mentions "daemon" or "polling" or "runs"
        6. uv run pykoclaw tasks --help
        7. Assert: Output mentions "list" or "show"
      Expected Result: Help text accurately describes commands
      Evidence: CLI output captured
    ```

    **Commit**: YES
    - Message: `docs(cli): improve help text for scheduler and tasks commands`
    - Files: `src/pykoclaw/__main__.py`
    - Pre-commit: `uv run pykoclaw --help`

---

- [x]   8. Create feature branches and commit all changes

    **What to do**:
    - Each subdirectory is a separate git repo. Create `feat/delivery-queue` branches and commit:
        - `pykoclaw/`: Tasks 1, 2, 3, 6, 7 changes
        - `pykoclaw-whatsapp/`: Task 4 changes
        - `pykoclaw-acp/`: Task 5 changes
    - Make atomic commits per task (or logical group) as specified in each task's Commit section
    - Verify all tests pass before final commits

    **Must NOT do**:
    - Do NOT commit to main/master directly — use feature branches
    - Do NOT push to remote — just local branches
    - Do NOT commit in the workspace root repo (pykoclaw-dev) unless workspace-level files changed

    **Recommended Agent Profile**:
    - **Category**: `quick`
        - Reason: Git operations only
    - **Skills**: [`git-master`]
        - `git-master`: Branch creation and atomic commits across multiple repos

    **Parallelization**:
    - **Can Run In Parallel**: NO (final task)
    - **Parallel Group**: Wave 5 (alone)
    - **Blocks**: None
    - **Blocked By**: All previous tasks

    **References**:

    **Documentation References**:
    - `CLAUDE.md: "Each subdir is its own git repo. Commits go into the individual repos"` — multi-repo commit strategy

    **Acceptance Criteria**:
    - [x] `feat/delivery-queue` branch exists in `pykoclaw/`, `pykoclaw-whatsapp/`, `pykoclaw-acp/`
    - [x] All changes committed with descriptive messages (5 + 1 + 1 = 7 commits)
    - [x] `uv run pytest` passes from workspace root (162 passed, 4 pre-existing failures)
    - [x] `git status` shows clean working tree in all repos

    **Agent-Executed QA Scenarios:**

    ```
    Scenario: All repos have clean feature branches
      Tool: Bash (git)
      Preconditions: All tasks completed
      Steps:
        1. cd pykoclaw && git branch --list "feat/delivery-queue" && git status
        2. cd pykoclaw-whatsapp && git branch --list "feat/delivery-queue" && git status
        3. cd pykoclaw-acp && git branch --list "feat/delivery-queue" && git status
        4. uv run pytest
      Expected Result: Feature branches exist, working trees clean, tests pass
      Evidence: git + pytest output
    ```

    **Commit**: N/A (this IS the commit task)

---

## Commit Strategy

| After Task | Repo               | Message                                                  | Files                           | Verification                                     |
| ---------- | ------------------ | -------------------------------------------------------- | ------------------------------- | ------------------------------------------------ |
| 1          | pykoclaw/          | `feat(db): add delivery_queue table and CRUD`            | db.py, models.py, test_db.py    | `uv run pytest pykoclaw/tests/test_db.py`        |
| 2          | pykoclaw/          | `feat(scheduler): enqueue delivery after task execution` | scheduler.py, test_scheduler.py | `uv run pytest pykoclaw/tests/test_scheduler.py` |
| 3          | pykoclaw/          | `feat(tools): add target_conversation to schedule_task`  | tools.py, db.py, models.py      | `uv run pytest pykoclaw/tests/`                  |
| 4          | pykoclaw-whatsapp/ | `feat(whatsapp): add delivery queue polling`             | connection.py                   | `uv run pytest pykoclaw-whatsapp/`               |
| 5          | pykoclaw-acp/      | `feat(acp): add delivery queue polling`                  | server.py or client_pool.py     | `uv run pytest pykoclaw-acp/`                    |
| 6          | pykoclaw/          | `test(delivery): integration tests for delivery flow`    | test_delivery.py                | `uv run pytest pykoclaw/tests/`                  |
| 7          | pykoclaw/          | `docs(cli): improve help text for scheduler and tasks`   | **main**.py                     | `uv run pykoclaw --help`                         |

---

## Future Phases (NOT in this plan)

### Phase 2 — Cross-Channel Routing & Fallback

- `channel_heartbeats` table for tracking active channels
- Heartbeat write from each channel plugin
- Fallback logic: if originating channel is dead for >N minutes, try next active channel
- `get_channel_prefix()` on plugin protocol (or separate interface)

### Phase 3 — Semantic Conversation Matching

- `find_conversation` MCP tool for natural language conversation targeting
- Content indexing or search across conversation data
- "The channel where we talked about lunch with friends" → searches conversation history
- Requires conversation summaries or topic extraction infrastructure

---

## Success Criteria

### Verification Commands

```bash
uv run pytest                              # All tests pass
uv run pykoclaw tasks --help               # Shows "List all scheduled tasks"
uv run pykoclaw scheduler --help           # Shows daemon description
```

### Final Checklist

- [x] `delivery_queue` table exists with proper schema
- [x] Scheduler writes results to queue after each task execution
- [x] WhatsApp plugin polls queue and delivers via OutgoingQueue.send()
- [x] ACP plugin polls queue and delivers via session/update (best-effort)
- [x] `schedule_task` tool accepts optional `target_conversation`
- [x] CLI help text is accurate and descriptive
- [x] Integration tests pass (8 integration + 4 DB delivery + 6 scheduler tests)
- [x] All changes on `feat/delivery-queue` branches in respective repos
- [x] No regressions in existing tests

### Execution Summary

**Completed**: 2026-02-15 (~11 minutes execution time)

**Commits**:

| Repo | Hash | Message |
|------|------|---------|
| pykoclaw/ | `c1332ea` | `feat(db): add delivery_queue table, DeliveryQueueItem model, and CRUD functions` |
| pykoclaw/ | `aaa0b71` | `feat(scheduler): enqueue delivery after task execution and set WAL mode` |
| pykoclaw/ | `f388c19` | `feat(tools): add target_conversation parameter to schedule_task` |
| pykoclaw/ | `1bd191d` | `docs(cli): improve help text for scheduler and tasks commands` |
| pykoclaw/ | `545c42d` | `test(delivery): add integration tests for delivery queue flow` |
| pykoclaw-whatsapp/ | `3b919aa` | `feat(whatsapp): add delivery queue polling for scheduled task results` |
| pykoclaw-acp/ | `586e2f2` | `feat(acp): add delivery queue polling for scheduled task results` |

**Test Results**: 162 passed, 4 pre-existing ACP failures (wrong mock target in `test_server.py` — existed on `main` before changes)

**Note**: 4 pre-existing ACP test failures patch `pykoclaw_acp.server.dispatch_to_agent` but `dispatch_to_agent` is imported in `client_pool.py`, not `server.py`. This is unrelated to the delivery queue work.
