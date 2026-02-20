# Anyio Cancel Scope Leak in asyncio Tasks

**Tags:** acp, anyio, asyncio, cancel-scope, bug
**Related:** [acp-debugging.md], [asyncio-shutdown-gotcha.md]

## Problem

`ClaudeSDKClient.disconnect()` calls `Query.close()` which does
`self._tg.cancel_scope.cancel()`. When called from an asyncio task
(e.g. `_sweep_loop`), the anyio `CancelledError` escapes into the
asyncio event loop and cancels whatever `await` is active in the
**calling** task — even unrelated ones like `reader.readline()`.

## Symptoms

- Tight loop of `CancelledError` on `readline()` (45k+ in 8 min)
- ACP process pegged at 100% CPU, can't read stdin
- Mitto shows "Connection lost" to the user

## Fix

1. Wrap `client.disconnect()` in `asyncio.shield()` — prevents the
   cancel scope from propagating.
2. Add `CancelledError` handler in server main loop as safety net,
   with `await asyncio.sleep(0.5)` backoff and consecutive-error limit.

## Rule

**Never call `ClaudeSDKClient.disconnect()` without `asyncio.shield()`**
when running inside a task that shares the event loop with other
important coroutines.

[acp-debugging.md]: acp-debugging.md
[asyncio-shutdown-gotcha.md]: asyncio-shutdown-gotcha.md
