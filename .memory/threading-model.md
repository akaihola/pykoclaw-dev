# WhatsApp Threading Model

**Tags:** whatsapp, sqlite, threading
**Related:** [neonize-quirks.md], [channel-dispatch.md]

The WhatsApp plugin runs **3 threads** sharing a single SQLite connection:

1. **Main thread** — runs `neonize.connect()` (blocks)
2. **Go callback thread** — Neonize/whatsmeow fires `on_message()` here
3. **asyncio event loop thread** — daemon thread running `query_agent()`

All bridge DB access goes through `ThreadSafeConnection` (a `threading.Lock`
wrapper) to prevent sqlite3 corruption from concurrent C-level access.

With multi-agent routing, each agent with a `data_dir` gets its own DB
(opened lazily by `_get_agent_db()`). Per-agent DBs are only accessed from
the asyncio event loop thread, so they don't need `ThreadSafeConnection`.

[neonize-quirks.md]: neonize-quirks.md
[channel-dispatch.md]: channel-dispatch.md
