# asyncio.run() Shutdown Hangs Forever

**Tags:** asyncio, gotcha, acp, mitto, zombie
**Related:** [acp-debugging.md]

## The bug

`asyncio.run()` calls `_cancel_all_tasks()` during cleanup, which does
`loop.run_until_complete(gather(*tasks))` with **no timeout**.  If any task
has non-cancellable work (e.g. a Claude SDK subprocess that won't exit),
the process hangs forever.

A wrapper that cancels tasks with a bounded timeout (like
`_run_with_graceful_shutdown`) doesn't help — `asyncio.run()` runs its
**own** unbounded `_cancel_all_tasks()` *after* the wrapper returns.

## The fix

Don't use `asyncio.run()`.  Manage the event loop manually:

```python
loop = asyncio.new_event_loop()
try:
    loop.run_until_complete(main())
finally:
    _cancel_remaining_tasks(loop)   # bounded timeout + os._exit()
    loop.run_until_complete(loop.shutdown_asyncgens())
    loop.close()
```

In `_cancel_remaining_tasks`, call `os._exit(0)` if tasks don't cancel
within the timeout.  This is safe as long as graceful cleanup
(`server.stop()`) already ran.

## Zombie chain

Hang → watchdog SIGKILL → Mitto doesn't `waitpid()` → zombie →
Mitto writes to dead pipe → "broken pipe" → all sessions broken.

[acp-debugging.md]: acp-debugging.md
