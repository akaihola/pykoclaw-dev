# Refactor Shared Code to pykoclaw-messaging (Phase 2: Parameterized)

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: Refactor BatchAccumulator and database helper functions to accept platform parameters, enabling shared implementations in pykoclaw-messaging while still supporting WhatsApp's Go-thread bridge and Matrix's native async model.
>
> **Deliverables**:
>
> - `pykoclaw_messaging/handler.py` - Parameterized BatchAccumulator supporting both async and thread-safe modes
> - `pykoclaw_messaging/db.py` - Parameterized DB helper functions (store_message, get_new_messages, update_cursor)
> - Updated WhatsApp plugin to use parameterized helpers
> - Updated Matrix plugin to use parameterized helpers
>
> **Estimated Effort**: Medium
> **Depends On**: messaging-shared-code-phase1

---

## Context

### Current State

Phase 1 moves identical code to pykoclaw-messaging. Phase 2 addresses code that's similar but has platform-specific differences:

1. **BatchAccumulator** - Same logic, but:
   - WhatsApp: Uses `asyncio.run_coroutine_threadsafe()` to bridge Go threads to Python asyncio
   - Matrix: Uses native asyncio since matrix-nio is fully async

2. **Database helpers** - Same logic, but different table/column names:
   - WhatsApp: `wa_messages`, `wa_chats` tables
   - Matrix: `matrix_messages`, `matrix_rooms` tables

3. **\_is_hard_mention()** - Nearly identical, but:
   - WhatsApp regex: Doesn't include `(?<=,\s)`
   - Matrix regex: Includes `(?<=,\s)` for comma-separated mentions

### Why This Matters

- **Complete deduplication**: After Phase 1 + 2, only truly platform-specific code remains
- **Easier maintenance**: Single implementation of shared logic
- **Foundation for new plugins**: ACP/Telegram could use the same parameterized helpers

### Technical Path

Create parameterized versions that accept platform-specific configuration. Both plugins pass their own config.

---

## Work Objectives

### Core Objective

Refactor BatchAccumulator and DB helpers to be parameterized, enabling single shared implementations.

### Must Have

#### 1. Create pykoclaw_messaging/handler.py

**BatchAccumulator with thread-safe mode:**

```python
class BatchAccumulator:
    def __init__(
        self,
        *,
        window_seconds: float,
        flush_callback: Callable[[str, bool], Awaitable[None]],
        use_threadsafe: bool = False,  # NEW: for Go-thread bridge
        loop: asyncio.AbstractEventLoop | None = None,  # NEW: for threadsafe
    ) -> None:
        ...
```

- When `use_threadsafe=True`: Use `asyncio.run_coroutine_threadsafe()` for add() calls
- When `use_threadsafe=False`: Use native asyncio (current Matrix behavior)
- Include `_is_hard_mention()` with configurable regex pattern

**DB helper factory or class:**

```python
def create_db_helpers(table_prefix: str) -> tuple[
    store_message,      # fn(db, chat_id, sender, text, timestamp, is_from_me)
    get_new_messages,   # fn(db, chat_id) -> list[tuple]
    update_cursor,      # fn(db, chat_id, timestamp)
    update_timestamp,  # fn(db, chat_id, timestamp)
]:
    """Create platform-specific DB helpers with table_prefix."""
    # e.g., "wa" -> wa_messages, wa_chats
    # e.g., "matrix" -> matrix_messages, matrix_rooms
```

#### 2. Update pykoclaw-whatsapp

- Import BatchAccumulator from pykoclaw_messaging
- Pass `use_threadsafe=True` and `loop` parameter
- Import DB helpers, pass `table_prefix="wa"`

#### 3. Update pykoclaw-matrix

- Import BatchAccumulator from pykoclaw_messaging
- Use default `use_threadsafe=False`
- Import DB helpers, pass `table_prefix="matrix"`

### Should Have

- Type hints for all parameterized functions
- Docstrings explaining the parameters

### Verification

- [ ] WhatsApp message batching works (debounce, hard mention flush)
- [ ] Matrix message batching works (debounce, hard mention flush)
- [ ] Both plugins correctly track cursors and timestamps
- [ ] Unit tests for parameterized helpers pass

---

## Dependencies

- **Required**: messaging-shared-code-phase1 (Phase 1 must complete first)

---

## Notes

- The WhatsApp handler.py already has all the needed logic - this is mostly parameterization work
- Matrix handler.py can be largely replaced by imports after this
- Consider whether the handler.py should stay in the plugins or move entirely to messaging (probably stay in plugins for now since they're small)
