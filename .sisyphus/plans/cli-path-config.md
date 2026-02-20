# Add CLI Path Config to Pykoclaw

## Status: Done

## TL;DR

> **Quick Summary**: Add a configurable `cli_path` setting to pykoclaw so it uses the system Claude (2.1.42) instead of the bundled Claude (2.1.39) which is crashing.
> 
> **Deliverables**: 
> - Config setting in `pykoclaw/config.py`
> - Used in `client_pool.py` when creating ClaudeAgentOptions
> - Documentation in README
> 
> **Estimated Effort**: Short
> **Parallel Execution**: NO - sequential

---

## Context

### Original Problem
- pykoclaw-acp uses the bundled Claude CLI (2.1.39) from the claude_agent_sdk
- When connecting through CCM (Claude Code Mux), 2.1.39 crashes with "peer disconnected before response"
- The user's system Claude (2.1.42) works fine
- Sessions in Mitto are stuck because the backend keeps dying

### Root Cause
- Claude CLI version mismatch: bundled 2.1.39 crashes, system 2.1.42 works
- The SDK has a `cli_path` option that can point to a different Claude binary

---

## Work Objectives

### Core Objective
Make pykoclaw use the system Claude CLI instead of the bundled one.

### Concrete Deliverables
- New `cli_path` config setting in `pykoclaw/config.py`
- Used in `pykoclaw-acp/src/pykoclaw_acp/client_pool.py` when creating `ClaudeAgentOptions`
- Environment variable: `PYKOCLAW_CLI_PATH`

### Definition of Done
- [x] `PYKOCLAW_CLI_PATH=/home/agent/.local/bin/claude pykoclaw acp` uses system Claude
- [x] Mitto sessions work without "peer disconnected" errors
- [x] Claude version reported is 2.1.42 (or whatever system version is)

### Must Have
- Works with unset `cli_path` (defaults to bundled)
- Setting works via environment variable `PYKOCLAW_CLI_PATH`

### Must NOT Have
- Breaking changes to existing functionality

---

## Verification Strategy

### Agent-Executed QA Scenarios

**Scenario: Verify cli_path setting works**
  Tool: Bash
  Preconditions: None
  Steps:
    1. Check current bundled Claude version: `/home/agent/pykoclaw/.venv/lib/python3.13/site-packages/claude_agent_sdk/_bundled/claude --version`
    2. Check system Claude version: `which claude && claude --version`
    3. Export PYKOCLAW_CLI_PATH to system claude
    4. Verify the setting loads: `cd /home/agent/pykoclaw && uv run python3 -c "from pykoclaw.config import settings; print(settings.cli_path)"`
  Expected Result: Setting is read correctly
  Evidence: Python output shows the path

**Scenario: Verify Mitto sessions work**
  Tool: interactive_bash (tmux)
  Preconditions: Mitto running, pykoclaw restarted with new setting
  Steps:
    1. Kill existing pykoclaw processes: `pkill -f "pykoclaw acp"`
    2. Wait for Mitto to restart them
    3. Send a test message in Mitto
    4. Wait for response
  Expected Result: Response arrives without "peer disconnected" error
  Evidence: Mitto event log shows agent_message, no errors

---

## TODOs

- [x] 1. Add cli_path setting to pykoclaw/config.py

  **What to do**:
  - Add `cli_path: Path | None = None` to Settings class
  - Use `Path.home() / ".local" / "bin" / "claude"` as the default path when not set, but keep the default as None to use bundled
  
  **Must NOT do**:
  - Change existing defaults

  **References**:
  - `pykoclaw/src/pykoclaw/config.py:18` - existing settings pattern
  
  **Acceptance Criteria**:
  - [x] Setting exists and defaults to None (use bundled)
  - [x] `PYKOCLAW_CLI_PATH=/path/to/claude` sets the value

- [x] 2. Pass cli_path to ClaudeAgentOptions in client_pool.py

  **What to do**:
  - Import the cli_path from settings
  - Add `cli_path=settings.cli_path` to ClaudeAgentOptions call
  
  **References**:
  - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:131-138` - where ClaudeAgentOptions is created
  
  **Acceptance Criteria**:
  - [x] When cli_path is set, Claude uses that binary
  - [x] When cli_path is None, bundled Claude is used (default behavior unchanged)

---

## Success Criteria

### Verification Commands
```bash
# Test config loads
cd /home/agent/pykoclaw && PYKOCLAW_CLI_PATH=/home/agent/.local/bin/claude uv run python3 -c "from pykoclaw.config import settings; print(settings.cli_path)"
# Expected: /home/agent/.local/bin/claude
```

### Final Checklist
- [x] cli_path setting added to config
- [x] Setting passed to ClaudeAgentOptions
- [x] Works with environment variable
- [x] Default (None) uses bundled Claude
- [x] Mitto sessions work without crashes
