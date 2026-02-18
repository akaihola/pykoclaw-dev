# ACP / Mitto Debugging Playbook

**Tags:** acp, mitto, debugging, claude-sdk
**Related:** [acp-protocol-fix.md], [mitto-setup.md]

## Architecture (data flow)

```
User → Mitto web UI → Mitto Go process (PID on pts/6)
  → pykoclaw subprocess (stdio pipes)
    → dispatch_to_agent() → ClaudeSDKClient → claude CLI subprocess
```

## Key log & data locations

| What                  | Where                                                          |
| --------------------- | -------------------------------------------------------------- |
| Mitto sessions        | `~/.local/share/mitto/sessions/<id>/events.jsonl`              |
| Mitto session meta    | `~/.local/share/mitto/sessions/<id>/metadata.json`             |
| Mitto workspaces      | `~/.local/share/mitto/workspaces.json`                         |
| Mitto settings        | `~/.local/share/mitto/settings.json`                           |
| Mitto systemd logs    | `journalctl --user -u mitto-web --no-pager -n 100`            |
| Pykoclaw DB (main)    | `~/.local/share/pykoclaw/pykoclaw.db`                          |
| Pykoclaw DB (per-cwd) | `<cwd>/pykoclaw.db` (e.g. `~/my-knowledge/pykoclaw.db`)       |
| Claude CLI debug logs | `~/.claude/debug/<session-id>.txt` (latest → `debug/latest`)  |
| Claude CLI sessions   | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`          |
| Pykoclaw ACP stderr   | Goes to Mitto's stderr → `/dev/pts/6` (terminal)              |

## Debugging steps (in order)

### 1. Check Mitto session events

```bash
ls -lt ~/.local/share/mitto/sessions/           # find latest session
cat ~/.local/share/mitto/sessions/<id>/events.jsonl  # see all events
cat ~/.local/share/mitto/sessions/<id>/metadata.json # check status, updated_at
```

- `user_prompt` with no following `agent_message` = response never arrived
- `updated_at` == `last_user_message_at` = Mitto's `Prompt()` never returned

### 2. Check processes

```bash
ps aux | grep pykoclaw | grep -v grep          # find pykoclaw processes
pstree -p <mitto-pid>                           # see mitto's children
cat /proc/<pid>/wchan                           # what it's blocked on
cat /proc/<pid>/status | grep -E "State|Threads"
ls -la /proc/<pid>/cwd                          # verify working directory
```

- `do_epoll_wait` = idle on asyncio event loop (waiting for stdin)
- Zombie `<defunct>` = old process, parent hasn't reaped it
- Multiple pykoclaw children of mitto = old zombies + current active one

### 3. Check pykoclaw DB

```bash
uv run python -c "
import sqlite3; conn = sqlite3.connect('<path>/pykoclaw.db')
conn.row_factory = sqlite3.Row; c = conn.cursor()
c.execute('SELECT * FROM conversations ORDER BY created_at DESC')
for r in c.fetchall(): print(dict(r))
"
```

- `session_id` present = `dispatch_to_agent` completed at least once
- `session_id` unchanged after second prompt = second prompt never reached `query_agent`

### 4. Check Claude CLI debug logs

```bash
ls -lt ~/.claude/debug/ | head -5              # find latest debug file
cat ~/.claude/debug/latest                     # read it
grep "SessionEnd\|Error\|WARN" ~/.claude/debug/latest
```

- `SessionEnd with query: other` immediately after startup = CLI exited prematurely
- `SessionStart` present = CLI started successfully
- Look for `"No conversation found with session ID"` in result JSON

### 5. Add temporary debug logging to pykoclaw ACP

In `pykoclaw-acp/src/pykoclaw_acp/__init__.py`, change logging config:

```python
log_file = open("/tmp/pykoclaw-acp-debug.log", "a")
logging.basicConfig(
    stream=log_file,
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
```

Then add `log.error(...)` calls in `server.py`'s `_dispatch` and `_write`.
Kill the pykoclaw process to force Mitto to respawn it with new code.

### 6. Reproduce manually

```bash
# Test claude CLI resume directly
claude --resume <session-id> --output-format stream-json \
    --input-format stream-json --permission-mode bypassPermissions \
    -p "test" 2>&1 | head -50
```

## Key gotchas learned

- Mitto spawns pykoclaw as a child subprocess. Killing pykoclaw makes Mitto
  respawn it on next message (with fresh `_sessions` dict).
- `mitto web` on pts/6 is usually the real instance. The systemd service
  may crash-loop if port 8080 is already bound.
- Pykoclaw logging goes to stderr (level=ERROR), which Mitto pipes to its own
  stderr. Can't capture it remotely — redirect to a file for debugging.
- The ACP SDK's `acp.Connection.Prompt()` blocks until a response with matching
  JSON-RPC `id` arrives. If pykoclaw never sends the response (e.g. unhandled
  exception in `run()` loop catches it but no response sent), Mitto hangs.
- `ClaudeSDKClient` resume doesn't work across process restarts — the session
  JSONL only gets a `dequeue` operation, not full conversation data.
- **Zombie chain:** `asyncio.run()` cleanup hangs → watchdog SIGKILLs →
  Mitto doesn't `waitpid()` → zombie → "broken pipe" on next prompt.
  See [asyncio-shutdown-gotcha.md] for the fix.
- **Restarting Mitto:** If the old process still holds port 8080, `kill <old-pid>`
  first, then `systemctl --user restart mitto-web`. The systemd restart alone
  will crash-loop on "address already in use".
- **Faulthandler traces:** `~/.local/state/pykoclaw/faulthandler-<pid>.txt` —
  non-empty files contain watchdog-captured tracebacks showing where the event
  loop was stuck.

[acp-protocol-fix.md]: acp-protocol-fix.md
[asyncio-shutdown-gotcha.md]: asyncio-shutdown-gotcha.md
[mitto-setup.md]: mitto-setup.md
