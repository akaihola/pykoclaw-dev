# Decisions — ACP Crash Resilience

This notepad tracks architectural and implementation decisions.

---

## Error Notification Format
**Decision**: Use `session/update` notification with `"sessionUpdate": "error"` instead of JSON-RPC error response.
**Reason**: The ack is sent BEFORE dispatch starts (line 144), so by the time dispatch fails, Mitto already got "ok". A notification follows the existing streaming pattern.

## Error Message Content
**Decision**: Generic user message ("Agent processing failed. Please try again."), full traceback in server logs only.
**Reason**: Tracebacks leak internals; users don't need Python stack traces.
