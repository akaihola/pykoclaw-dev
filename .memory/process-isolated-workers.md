# Process-Isolated SDK Workers

**Tags:** acp, architecture, worker, process-isolation
**Related:** [anyio-cancel-scope-leak.md], [asyncio-shutdown-gotcha.md]

## Architecture

The ACP server communicates with SDK worker subprocesses over
stdin/stdout pipes using a JSON-newline protocol. One worker per
ACP session. Workers own the entire anyio/SDK stack.

```
AcpServer (pure asyncio) → WorkerPool
  → worker subprocess 1 (anyio + ClaudeSDKClient)
  → worker subprocess 2 (anyio + ClaudeSDKClient)
```

## Key files

| File | Purpose |
|------|---------|
| `pykoclaw/src/pykoclaw/sdk_consume.py` | Shared SDK response consumer |
| `pykoclaw-acp/src/pykoclaw_acp/worker_protocol.py` | JSON-newline protocol |
| `pykoclaw-acp/src/pykoclaw_acp/worker.py` | Worker subprocess entry point |
| `pykoclaw-acp/src/pykoclaw_acp/worker_pool.py` | WorkerPool (manages workers) |

## Eliminated problems

- anyio cancel scope leaks (different process)
- `_kill_client()` hack (workers call `disconnect()` safely)
- `os._exit()` forced shutdown (workers exit normally)
- Two SDK message loops (unified in `sdk_consume.py`)

[anyio-cancel-scope-leak.md]: anyio-cancel-scope-leak.md
[asyncio-shutdown-gotcha.md]: asyncio-shutdown-gotcha.md
