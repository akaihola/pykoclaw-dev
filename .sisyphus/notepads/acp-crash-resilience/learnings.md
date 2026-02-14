# Learnings — ACP Crash Resilience

This notepad tracks patterns, conventions, and discoveries during implementation.

---

## Timestamp Format
*To be updated during execution*

## Error Handling Pattern in ACP

**Pattern**: Wrap async dispatch calls in try/except Exception blocks with error notifications.

The ACP server uses a JSON-RPC 2.0 protocol where:
1. Acknowledgment is sent BEFORE dispatch starts (line 144: `format_response(msg_id, {})`)
2. If dispatch fails AFTER the ack, send an error notification via `session/update` with `"sessionUpdate": "error"`
3. This prevents the client from seeing "Lost connection" when the server survives the error

**Key insight**: The ack-then-silence race is solved by sending a notification, not an error response, since the ack already consumed the message ID.

## Test Pattern for Error Handling

**Pattern**: Use `_collect_writes()` helper + `AsyncMock(side_effect=Exception)` to test error paths.

The existing test infrastructure in `test_server.py` provides:
- `_collect_writes()` (lines 37-47): Captures all JSON-RPC messages written by the server
- `AsyncMock` from unittest.mock: Simulates exceptions during dispatch
- Fixtures `tmp_db` and `server`: In-memory SQLite + AcpServer instance

This pattern allows testing error handling without mocking the entire dispatch pipeline.

## Main Loop Resilience

**Pattern**: Use `continue` instead of `break` in catch-all exception handlers in event loops.

The main loop (lines 39-64) processes stdin messages. The catch-all on line 61-63 now uses `continue` to recover from transient errors instead of killing the server. This allows the server to survive:
- Temporary dispatch failures (API timeouts, SDK errors)
- Transient database errors
- Other recoverable exceptions

**Guardrail**: Only catch `Exception`, not `BaseException`, to preserve clean shutdown via `CancelledError` and `SystemExit`.

## Implementation Completeness

All three tasks completed successfully:
1. ✅ Line 63: `break` → `continue` (one-word change)
2. ✅ Lines 160-167: `dispatch_to_agent()` wrapped in try/except with error notification
3. ✅ 4 new test functions added: error notification, server survival, main loop continuation, CancelledError propagation

**Test results**:
- 27 ACP tests pass (17 existing + 4 new error tests)
- 4 error-specific tests pass (via `-k "error"`)
- 150 full workspace tests pass (no regressions)
