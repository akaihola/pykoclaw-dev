# Anyio Cancel Scope Leak — Resolved via Process Isolation

**Tags:** acp, anyio, asyncio, cancel-scope, resolved
**Related:** [acp-debugging.md], [asyncio-shutdown-gotcha.md]

## Problem (historical)

`ClaudeSDKClient.disconnect()` calls `Query.close()` which does
`self._tg.cancel_scope.cancel()`. When called from an asyncio task,
the anyio `CancelledError` escapes into the asyncio event loop and
cancels whatever `await` is active in the **calling** task.

## Resolution (2026-02-21)

**Process-isolated workers** eliminate the root cause entirely. The
Claude SDK now runs in dedicated subprocess workers. The ACP server
is pure asyncio — no anyio code in-process, no cancel scope leaks.

Workers can safely call `client.disconnect()` because they own the
entire async runtime (anyio + asyncio, no sharing).

Key files:
- `pykoclaw-acp/src/pykoclaw_acp/worker.py` — worker subprocess
- `pykoclaw-acp/src/pykoclaw_acp/worker_pool.py` — replaces ClientPool
- `pykoclaw/src/pykoclaw/sdk_consume.py` — unified SDK consumption

## Rule

**Run the Claude SDK in a separate process from the ACP server.**
Never share an event loop between anyio (SDK) and asyncio (server).

[acp-debugging.md]: acp-debugging.md
[asyncio-shutdown-gotcha.md]: asyncio-shutdown-gotcha.md
