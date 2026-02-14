# Decisions — Code Review Fixes

## Commit Strategy
- 13 sequential commits, each gated by full test suite
- Test command: `uv run pytest pykoclaw/tests/ pykoclaw-whatsapp/tests/ --tb=short -q`
- Chat tests excluded (broken pre-existing)

## Git Workflow
- Workspace root: `/home/agent/pykoclaw/`
- Subpackages are separate git repos:
  - `pykoclaw/` (core)
  - `pykoclaw-chat/` (chat plugin)
  - `pykoclaw-whatsapp/` (whatsapp plugin)
- **All commits must be made INSIDE the relevant subpackage directory**

## Guardrails
- MUST NOT change SQLite schema
- MUST NOT rename `ScheduledTask.id` model field (only function parameters)
- MUST NOT add new pip dependencies
- MUST NOT refactor code adjacent to fix targets
- MUST NOT change behavior except where explicitly fixing bugs (#2, #3, #5)
