# Claude SDK Subprocess Stderr is Silently Discarded by Default

**Tags:** claude-sdk, debugging, gotcha, whatsapp, logging
**Related:** [session-resume-retry.md], [debugging-workflow.md]

## The problem

`ClaudeAgentOptions.stderr` defaults to `None`. When `None`, the SDK spawns
the `claude` subprocess with `stderr=None` (not piped), so every error,
warning, and crash message from the CLI is silently dropped. You get an
opaque `ProcessError` or an empty result with no explanation.

This is why "chose silence" bugs are so hard to diagnose — the real error
lives in a void.

## The fix — always in `agent_core.py`

Wire a `stderr` callback in `ClaudeAgentOptions`:

```python
_sdk_stderr_log = logging.getLogger("claude_agent_sdk.stderr")

def _on_stderr(line: str) -> None:
    _sdk_stderr_log.debug("[%s] %s", conversation_name, line)

options = ClaudeAgentOptions(
    ...
    stderr=_on_stderr,
)
```

This activates stderr piping on the subprocess. Output is logged at DEBUG
level under `claude_agent_sdk.stderr`. Enable with `PYKOCLAW_LOG_LEVEL=DEBUG`.

## Claude debug files are written regardless

Even without the callback, claude writes a full debug log to:

```
~/.claude/debug/<session_id>.txt
```

This is always written. When diagnosing a silent failure, find the session ID
from the DB or log and check this file immediately — it shows every startup
step, MCP connection, API call, and error the CLI saw.

[session-resume-retry.md]: session-resume-retry.md
[debugging-workflow.md]: debugging-workflow.md
