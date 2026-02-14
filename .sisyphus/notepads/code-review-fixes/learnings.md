# Learnings — Code Review Fixes

## [2026-02-12] Task 0: Baseline Test State
- Core: 30 tests passed in 1.62s
- WhatsApp: 80 tests passed in 1.94s
- Total: 110 tests passing (baseline established)
- Chat tests excluded (broken pre-existing: ModuleNotFoundError)

## [2026-02-12] Task 1: Delete Dead agent.py
- File `pykoclaw/src/pykoclaw/agent.py` successfully deleted (98 lines)
- No remaining imports found
- `agent_core.py` is the canonical implementation
- All 110 tests still pass after deletion
- Commit: `8f593fa` in `pykoclaw/` subdirectory
- **Git Structure Discovery**: Workspace has git repos INSIDE subdirectories (submodule pattern)
  - Commits must be made INSIDE each subpackage directory: `cd pykoclaw && git commit`
  - NOT at workspace root

## [2026-02-12] Task 2: Fix queue.py (Review #3, #8, #9)
- Successfully added thread-safety using `threading.RLock()` (reentrant for flush→send calls)
- Replaced `list` with `collections.deque` for O(1) popleft operations
- Removed orphan class-level `_queue` field
- Removed `_flushing` flag (lock replaces it)
- All 80 whatsapp tests pass (11 queue-specific tests)
- Commit: `1a9ab28` in `pykoclaw-whatsapp/` subdirectory
- Pattern followed: `ThreadSafeConnection` from `pykoclaw/src/pykoclaw/db.py:13-57`

## Task 3: Auth.py Threading Pattern Fix

**Completed**: 2026-02-12

### Pattern Applied
- Replaced `asyncio.create_task(shutdown_client(client))` with `threading.Event`
- Converted `async def run_auth()` to plain `def run_auth()`
- Removed `import asyncio` from auth.py
- Removed `asyncio.run()` wrapper from __init__.py

### Implementation Details
- Created `connected = threading.Event()` to signal authentication completion
- Wrapped `client.connect()` in daemon thread: `threading.Thread(target=client.connect, daemon=True)`
- Main thread waits with timeout: `connected.wait(timeout=120)`
- Added 1-second delay before disconnect to flush credentials
- Callback sets event: `connected.set()` in `on_connected()`

### Key Insight
The original pattern was broken because:
1. `client.connect()` blocks the main thread
2. `asyncio.create_task()` requires an active event loop
3. No event loop was running (blocking call prevents it)
4. Coroutine was created but never executed

Threading.Event solves this by:
- Running blocking call on daemon thread
- Main thread waits for signal from callback
- No async machinery needed
- Matches pattern used in connection.py:103-104

### Test Results
- All 110 tests pass (30 core + 80 whatsapp)
- No regressions introduced
- Commit: 891a27b


## Task 4: Fix compute_next_run() - "once" handling

**Status**: ✅ COMPLETED

**Changes**:
- Modified `pykoclaw/src/pykoclaw/scheduling.py`
- Added explicit `if schedule_type == "once": return schedule_value` branch
- Changed final fallback from `return schedule_value` to `return None`
- Updated docstring to document all four schedule type behaviors

**Verification**:
- Unknown type ("bogus") → returns None ✅
- "once" type → returns value as-is ✅
- Full test suite: 113 tests pass ✅
- No LSP diagnostics ✅

**Commit**: `4830fee` in pykoclaw/ subdirectory
- Message: "fix: handle \"once\" explicitly in compute_next_run, return None for unknown types"

**Key Learning**: The fix clarifies the API contract - "once" is a known type that returns the timestamp as-is, while truly unknown types return None. This matches the docstring promise and prevents ambiguity.

## Task 9: Move asyncio import to module top level (Review #14)

**Status**: ✅ ALREADY COMPLETED (as part of Task 3)

**Discovery**:
- Task 3 (auth.py fix) removed `import asyncio` from inside `register_commands` method
- This was the correct fix because asyncio is no longer needed after converting `run_auth()` to a regular function
- The task description said to "move" asyncio to module top level, but removing it was the correct action
- asyncio is not used anywhere in `__init__.py`, so importing it would be unnecessary

**Current State**:
- No `import asyncio` at module top level
- No `import asyncio` inside `register_commands`
- All 114 tests pass
- Code is correct and working as expected

**Key Learning**: The task description was based on the original code review, which identified that asyncio should be moved to the top level. However, the auth fix (Task 3) removed the need for asyncio entirely, making the task moot. The correct fix was to remove the import, not to move it.


## Task 11: DbConnection Type Alias Consistency (Review Item #7)

**Date**: 2026-02-12

### Changes Made

Replaced all bare `sqlite3.Connection` type hints with `DbConnection` type alias across both packages:

**Core package** (`pykoclaw/`):
- `__main__.py`: Return type of `_get_db_and_data_dir()`
- `agent_core.py`: Parameter type in `query_agent()`
- `tools.py`: Parameter type in `make_mcp_server()`
- `scheduler.py`: Parameter types in `run_task()` and `run_scheduler()`
- `plugins.py`: Protocol method `get_mcp_servers()`, base class method, and `run_db_migrations()`

**WhatsApp plugin** (`pykoclaw-whatsapp/`):
- `__init__.py`: Plugin method `get_mcp_servers()`
- `handler.py`: All functions (`store_message`, `update_chat_timestamp`, `update_global_cursor`, `update_agent_cursor`, `get_new_messages_for_chat`, `MessageHandler.__init__`)
- `connection.py`: `WhatsAppConnection.__init__()`

### Pattern Learned

**Type alias consistency**:
- The `DbConnection` type alias exists to handle the union of `sqlite3.Connection | ThreadSafeConnection`
- Using the alias everywhere (except the definition itself) ensures type safety when the runtime type is the wrapper
- Import pattern: `from pykoclaw.db import DbConnection` at the top of each file
- No logic changes needed—purely type hint updates

### Verification

- ✅ No bare `sqlite3.Connection` remains (except in `db.py` definition)
- ✅ `PykoClawPlugin` protocol imports correctly
- ✅ All 114 tests pass (33 core + 81 whatsapp)
- ✅ Commits created in both subdirectories

### Commits

- Core: `d757173 fix: use DbConnection type alias consistently in core package`
- WhatsApp: `0262498 fix(whatsapp): use DbConnection type alias consistently`
