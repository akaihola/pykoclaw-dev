# Pykoclaw Scheduler systemd User Services

## TL;DR

> **Quick Summary**: Add two systemd user services to the NixOS home-manager config that auto-start pykoclaw scheduler daemons for two data directories (Ressu/pipsa and Tyko/my-knowledge).
> 
> **Deliverables**:
> - Two new `systemd.user.services` blocks in `home-agent.nix`
> - `pykoclaw-scheduler-pipsa` service (PYKOCLAW_DATA=/home/agent/pipsa)
> - `pykoclaw-scheduler-tyko` service (PYKOCLAW_DATA=/home/agent/my-knowledge)
> 
> **Estimated Effort**: Quick
> **Parallel Execution**: NO — single task
> **Critical Path**: Task 1 (only task)

---

## Context

### Original Request
User wants the pykoclaw scheduler to start automatically for both `~/pipsa/` (Ressu) and `~/my-knowledge/` (Tyko) using systemd user services configured in `~/repos/nixos-config/`.

### Interview Summary
**Key Discussions**:
- Authentication: `ClaudeSDKClient` uses OAuth tokens from `~/.claude/.credentials.json`, populated by `claude /login`. No `ANTHROPIC_API_KEY` needed.
- Each data dir has a `.env` with `PYKOCLAW_DATA` and `PYKOCLAW_WA_TRIGGER_NAME`. The pydantic Settings loads `.env` from CWD, so `WorkingDirectory` in the service picks it up.
- Binary is at `%h/.local/bin/pykoclaw` (symlink from uv tools install).
- Existing `mitto-web` service in `home-agent.nix:41-55` provides the exact pattern to follow.

**Research Findings**:
- Binary confirmed: `/home/agent/.local/bin/pykoclaw` → symlink → uv tools
- `pykoclaw scheduler` confirmed as correct command (no extra flags)
- Both `.env` files confirmed present with correct contents
- Both `pykoclaw.db` databases confirmed present
- OAuth credentials confirmed at `~/.claude/.credentials.json`
- No existing pykoclaw scheduler services in systemd
- Settings `env_file` tuple: `(~/.local/share/pykoclaw/.env, ".env")` — later entries take precedence, so CWD `.env` wins

### Metis Review
**Identified Gaps** (addressed):
- OAuth token expiry could cause restart storms — addressed by systemd's default `StartLimitBurst=5` / `StartLimitIntervalSec=10s`; `claude /login` fixes this. No code change needed.
- Binary could temporarily disappear during `uv tool install` — addressed by `Restart=on-failure` + `RestartSec=5`
- Confirmed services are fully independent (separate databases, separate data dirs) — no inter-service ordering needed
- Confirmed `journalctl --user` is sufficient for log visibility (scheduler prints "Scheduler started" to stderr)

---

## Work Objectives

### Core Objective
Add two systemd user services to `home-agent.nix` that auto-start pykoclaw schedulers on user login, following the existing mitto-web service pattern.

### Concrete Deliverables
- Two service blocks added to `~/repos/nixos-config/home-manager/home-agent.nix`

### Definition of Done
- [x] `home-agent.nix` parses without Nix errors
- [x] Both services use correct ExecStart, WorkingDirectory, and Environment
- [x] Change committed to `~/repos/nixos-config` repo

### Must Have
- Service name: `pykoclaw-scheduler-pipsa` with `PYKOCLAW_DATA=/home/agent/pipsa`
- Service name: `pykoclaw-scheduler-tyko` with `PYKOCLAW_DATA=/home/agent/my-knowledge`
- `WorkingDirectory` set to respective data dir (so `.env` is loaded by pydantic Settings)
- `Environment` explicitly sets `PYKOCLAW_DATA` (belt-and-suspenders, env vars override `.env`)
- `ExecStart = "%h/.local/bin/pykoclaw scheduler"`
- Same reliability settings as mitto-web: `Type=simple`, `Restart=on-failure`, `RestartSec=5`
- `WantedBy = [ "default.target" ]` for auto-start on login
- Comment block above each service explaining its purpose (following mitto-web comment style)

### Must NOT Have (Guardrails)
- Do NOT modify any pykoclaw source code — this is a nix config change only
- Do NOT modify the `.env` files in either data directory
- Do NOT add `ANTHROPIC_API_KEY` anywhere — OAuth handles auth
- Do NOT add inter-service dependencies (`After = mitto-web` etc.) — services are independent
- Do NOT change the existing mitto-web service block
- Do NOT touch any file other than `~/repos/nixos-config/home-manager/home-agent.nix`
- Do NOT run `home-manager switch` or `nixos-rebuild switch` — user will do this after review
- Do NOT start or restart any services

---

## Verification Strategy (MANDATORY)

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks in this plan MUST be verifiable WITHOUT any human action.

### Test Decision
- **Infrastructure exists**: N/A (nix config, not Python code)
- **Automated tests**: None (nix file edit, verified by syntax check)
- **Framework**: N/A

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

> The agent verifies the deliverable by checking Nix syntax and inspecting the file content.

---

## Execution Strategy

### Single Task — No Parallelization

Only one file is being edited. Sequential execution is appropriate.

---

## TODOs

- [x] 1. Add two pykoclaw scheduler systemd services to home-agent.nix

  **What to do**:
  - Edit `~/repos/nixos-config/home-manager/home-agent.nix` to add two systemd user service blocks after the existing `mitto-web` service (after line 55, before the closing `}` on line 56)
  - Add `pykoclaw-scheduler-pipsa` service with:
    - Comment block: `# Pykoclaw scheduler for Ressu (pipsa) — polls every 60s for due tasks`
    - `Description = "Pykoclaw scheduler (pipsa/Ressu)"`
    - `After = [ "network.target" ]`
    - `Type = "simple"`
    - `ExecStart = "%h/.local/bin/pykoclaw scheduler"`
    - `WorkingDirectory = "/home/agent/pipsa"`
    - `Environment = "PYKOCLAW_DATA=/home/agent/pipsa"`
    - `Restart = "on-failure"`
    - `RestartSec = 5`
    - `WantedBy = [ "default.target" ]`
  - Add `pykoclaw-scheduler-tyko` service with:
    - Comment block: `# Pykoclaw scheduler for Tyko (my-knowledge) — polls every 60s for due tasks`
    - `Description = "Pykoclaw scheduler (my-knowledge/Tyko)"`
    - `After = [ "network.target" ]`
    - `Type = "simple"`
    - `ExecStart = "%h/.local/bin/pykoclaw scheduler"`
    - `WorkingDirectory = "/home/agent/my-knowledge"`
    - `Environment = "PYKOCLAW_DATA=/home/agent/my-knowledge"`
    - `Restart = "on-failure"`
    - `RestartSec = 5`
    - `WantedBy = [ "default.target" ]`
  - Commit to `~/repos/nixos-config` repo

  **Must NOT do**:
  - Modify the existing mitto-web service block
  - Touch any other file in the nixos-config repo
  - Run home-manager switch or start services
  - Add ANTHROPIC_API_KEY or inter-service dependencies

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file edit following an existing pattern, no complexity
  - **Skills**: [`git-master`]
    - `git-master`: Needed for committing to the nixos-config repo
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction needed
    - `frontend-ui-ux`: Not a UI task

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (only task)
  - **Blocks**: None
  - **Blocked By**: None

  **References** (CRITICAL - Be Exhaustive):

  **Pattern References** (existing code to follow):
  - `~/repos/nixos-config/home-manager/home-agent.nix:38-55` — The mitto-web service block. Follow this EXACT pattern for Unit/Service/Install structure, attribute naming, and comment style. The only differences should be: service name, Description, WorkingDirectory, and Environment.
  - `~/repos/nixos-config/home-manager/home-agent.nix:41` — Nix attribute set key format: `systemd.user.services.<name> = { ... };`

  **Configuration References** (values to use):
  - `/home/agent/pipsa/.env` — Contains `PYKOCLAW_DATA=/home/agent/pipsa` and `PYKOCLAW_WA_TRIGGER_NAME=Ressu`. The `PYKOCLAW_DATA` value goes into the `Environment` directive.
  - `/home/agent/my-knowledge/.env` — Contains `PYKOCLAW_DATA=/home/agent/my-knowledge` and `PYKOCLAW_WA_TRIGGER_NAME=Tyko`. Same usage.

  **Code References** (understanding the scheduler):
  - `/home/agent/pykoclaw/pykoclaw/src/pykoclaw/scheduler.py:86-95` — `run_scheduler()` is a `while True` loop that polls every 60 seconds. It's a long-running daemon, confirming `Type = "simple"` is correct.
  - `/home/agent/pykoclaw/pykoclaw/src/pykoclaw/config.py:10-11` — `env_file` tuple shows `.env` is loaded from CWD, confirming `WorkingDirectory` matters.

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios (MANDATORY):**

  ```
  Scenario: Nix file parses without errors
    Tool: Bash
    Preconditions: ~/repos/nixos-config exists, nix is available
    Steps:
      1. Run: nix-instantiate --parse ~/repos/nixos-config/home-manager/home-agent.nix 2>&1
      2. Assert: exit code is 0 (no parse errors)
      3. If nix-instantiate is not available, use: nix eval --file ... or grep for obvious syntax issues
    Expected Result: File parses cleanly
    Failure Indicators: Parse error messages, non-zero exit code
    Evidence: Command output captured

  Scenario: Both service blocks present with correct attributes
    Tool: Bash (grep)
    Preconditions: File has been edited
    Steps:
      1. grep "pykoclaw-scheduler-pipsa" ~/repos/nixos-config/home-manager/home-agent.nix
      2. Assert: match found
      3. grep "pykoclaw-scheduler-tyko" ~/repos/nixos-config/home-manager/home-agent.nix
      4. Assert: match found
      5. grep "PYKOCLAW_DATA=/home/agent/pipsa" ~/repos/nixos-config/home-manager/home-agent.nix
      6. Assert: match found
      7. grep "PYKOCLAW_DATA=/home/agent/my-knowledge" ~/repos/nixos-config/home-manager/home-agent.nix
      8. Assert: match found
      9. grep 'WorkingDirectory = "/home/agent/pipsa"' ~/repos/nixos-config/home-manager/home-agent.nix
      10. Assert: match found
      11. grep 'WorkingDirectory = "/home/agent/my-knowledge"' ~/repos/nixos-config/home-manager/home-agent.nix
      12. Assert: match found
      13. grep 'pykoclaw scheduler' ~/repos/nixos-config/home-manager/home-agent.nix
      14. Assert: at least 2 matches (one per service)
    Expected Result: All service attributes present
    Failure Indicators: grep returns no matches
    Evidence: grep output captured

  Scenario: Mitto-web service unchanged
    Tool: Bash
    Preconditions: File has been edited
    Steps:
      1. Read lines 41-55 of home-agent.nix
      2. Assert: mitto-web service block is identical to original
    Expected Result: mitto-web untouched
    Failure Indicators: Any difference in lines 41-55
    Evidence: File content captured
  ```

  **Evidence to Capture:**
  - [x] Nix parse output in terminal
  - [x] grep verification output
  - [x] File diff showing only the additions

  **Commit**: YES
  - Message: `feat(services): add pykoclaw scheduler systemd services for pipsa and tyko`
  - Files: `home-manager/home-agent.nix`
  - Pre-commit: `nix-instantiate --parse home-manager/home-agent.nix` (or equivalent syntax check)
  - Repo: `~/repos/nixos-config` (NOT the pykoclaw workspace)

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(services): add pykoclaw scheduler systemd services for pipsa and tyko` | `home-manager/home-agent.nix` | `nix-instantiate --parse` |

---

## Success Criteria

### Verification Commands
```bash
# Nix syntax check
nix-instantiate --parse ~/repos/nixos-config/home-manager/home-agent.nix
# Expected: clean parse, exit 0

# Service names present
grep -c "pykoclaw-scheduler" ~/repos/nixos-config/home-manager/home-agent.nix
# Expected: 2

# Both data dirs referenced
grep "PYKOCLAW_DATA" ~/repos/nixos-config/home-manager/home-agent.nix
# Expected: two lines with /home/agent/pipsa and /home/agent/my-knowledge
```

### Final Checklist
- [x] Both service blocks added following mitto-web pattern
- [x] `pykoclaw-scheduler-pipsa` has correct WorkingDirectory and Environment
- [x] `pykoclaw-scheduler-tyko` has correct WorkingDirectory and Environment
- [x] Mitto-web service unchanged
- [x] Nix file parses without errors
- [x] Committed to `~/repos/nixos-config`

### Post-Plan User Actions (NOT part of the plan)
After reviewing and approving the change:
1. `home-manager switch` (or `nixos-rebuild switch`) to apply
2. `systemctl --user status pykoclaw-scheduler-pipsa pykoclaw-scheduler-tyko` to verify
3. `journalctl --user -u pykoclaw-scheduler-pipsa -f` to watch logs
