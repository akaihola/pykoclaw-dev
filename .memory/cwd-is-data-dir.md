# Claude Code cwd is data_dir (workspace root)

**Tags:** agent-core, acp, chat, cwd, architecture
**Related:** [claude-sdk-setting-sources.md]

## What changed

`ClaudeAgentOptions.cwd` is set to `data_dir` (the workspace root) instead of
`data_dir/conversations/{name}/`. The per-conversation subdirectory was a
vestige of the earliest prototype – it was always empty and only caused the
agent's Bash/Read/Write tools to resolve relative paths against the wrong
directory.

## Affected sites

- `query_agent()` in `agent_core.py` – no longer creates `conv_dir`
- `_spawn_worker()` in `worker_pool.py` – passes `self._data_dir` as cwd
- `_run_chat()` in `pykoclaw-chat` – no per-conv dir or `CLAUDE.md` created

## Why it's safe

- Settings discovery unaffected (Claude Code walks up from cwd)
- The `cwd` column in `conversations` table is informational only
- No code reads from or writes meaningful data to `conversations/{name}/`
- Existing `conversations/` dirs are harmless (cleanup is out of scope)

[claude-sdk-setting-sources.md]: claude-sdk-setting-sources.md
