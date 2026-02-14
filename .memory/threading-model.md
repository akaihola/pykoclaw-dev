# WhatsApp Threading Model

**Tags:** whatsapp, sqlite, threading
**Related:** [neonize-quirks.md], [channel-dispatch.md]

The WhatsApp plugin runs **3 threads** sharing a single SQLite connection:

1. **Main thread** — runs `neonize.connect()` (blocks)
2. **Go callback thread** — Neonize/whatsmeow fires `on_message()` here
3. **asyncio event loop thread** — daemon thread running `query_agent()`

All DB access goes through `ThreadSafeConnection` (a `threading.Lock` wrapper)
to prevent sqlite3 corruption from concurrent C-level access.

If lock contention becomes a problem, consider: connection-per-thread with WAL
mode, a connection pool, or `aiosqlite` for the async side.

[neonize-quirks.md]: neonize-quirks.md
[channel-dispatch.md]: channel-dispatch.md
