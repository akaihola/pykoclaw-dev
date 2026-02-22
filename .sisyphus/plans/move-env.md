# Per-Agent Python Dependencies via Shared `~/.venv/`

## Status: Done

## Completed: 2026-02-22

## TL;DR

> **Quick Summary**: Claude Code runs skill scripts inside `~/.venv/`, but
> pykoclaw is installed in an isolated `uv tool` venv — so skills that invoke
> pykoclaw's MCP tools can't `import pykoclaw`. The fix has two parts: (1)
> `install-dev.sh` also installs pykoclaw + all plugins into `~/.venv/` so
> skills can import them; (2) each agent declares a `requirements.txt` for
> additional runtime deps (e.g. `defusedxml`, `lxml`), installed into `~/.venv/`
> at scheduler startup via `ExecStartPre` + `flock`.
>
> **Deliverables**:
>
> - `install-dev.sh` — add `uv pip install --python ~/.venv/bin/python -e`
>   step for pykoclaw + all plugins
> - Per-agent `$PYKOCLAW_DATA/requirements.txt` convention documented and in use
> - `ExecStartPre` flock + `uv pip install` line in all three scheduler services
>   (Väinö: manual unit ✅ / Tyko + Pipsa: via NixOS home-manager, pending deploy)
> - NixOS commit `9ad26b5` deployed via `home-manager switch`
>
> **Estimated Effort**: Short
> **Parallel Execution**: NO — sequential
> **Critical Path**: Task 1 → Task 2

---

## Context

### Problem

Claude Code executes skill scripts using `~/.venv/bin/python`. This virtualenv
has `include-system-site-packages = false` and is entirely separate from
pykoclaw's `uv tool` virtualenv. As a result:

1. **Skills can't import pykoclaw** — `import pykoclaw` inside a skill script
   fails because pykoclaw lives only in the tool venv, not in `~/.venv/`.
2. **Agent runtime deps are also missing** — packages like `defusedxml` and
   `lxml` (required by Anthropic's Office document skills) are not present in
   `~/.venv/` unless explicitly installed there.
3. **Three agents** (Tyko, Ressu/Pipsa, Väinö) share the same `~/.venv/` and
   their schedulers may start concurrently.

### Solution Design

**`install-dev.sh` installs into `~/.venv/`**: in addition to the existing
`uv tool install`, also install pykoclaw and all plugins into `~/.venv/` in
editable mode so Claude Code skill scripts can import them:

```bash
uv pip install --python ~/.venv/bin/python \
    -e ./pykoclaw \
    -e ./pykoclaw-messaging \
    -e ./pykoclaw-chat \
    -e ./pykoclaw-whatsapp \
    -e ./pykoclaw-acp \
    -e ./pykoclaw-matrix
```

This runs on every `install-dev.sh` invocation, so `~/.venv/` always reflects
the current editable source.

**Per-agent `requirements.txt`**: each agent declares additional Python
dependencies in `$PYKOCLAW_DATA/requirements.txt`. Agents without extra
packages simply omit the file.

**`ExecStartPre` with `flock` serialization**: each scheduler service installs
its agent's extra requirements into `~/.venv/` at startup:

```ini
ExecStartPre=/bin/sh -c 'test -f $PYKOCLAW_DATA/requirements.txt && flock /tmp/uv-venv-install.lock uv pip install --python %h/.venv/bin/python -r $PYKOCLAW_DATA/requirements.txt || true'
```

- `test -f ...` — skip entirely if no `requirements.txt`
- `flock /tmp/uv-venv-install.lock` — serialize concurrent installs; the lock
  file is ephemeral and auto-cleaned on reboot
- `uv pip install --python %h/.venv/bin/python` — installs into Claude Code's
  venv, NOT pykoclaw's tool venv
- `|| true` — never fail the service

**Why not a dedicated oneshot service?** The `flock` approach is simpler: no
extra unit, no `After=`/`Requires=` ordering complexity, and `uv pip install`
is idempotent when packages are already present.

### `~/.venv/` details

Created automatically by Claude Code:

```
home = /run/current-system/sw/bin
implementation = CPython
uv = 0.10.2
version_info = 3.13.11
include-system-site-packages = false
```

Currently installed packages (as of 2026-02-22):
`defusedxml 0.7.1`, `lxml 6.0.2`, `playwright 1.57.0`, `playwright-py-skill 0.1.0`.

---

## Work Objectives

### Core Objective

Claude Code skill scripts can import pykoclaw and all agent runtime
dependencies from `~/.venv/`, kept current by `install-dev.sh` and the
scheduler `ExecStartPre`.

### Concrete Deliverables

- `install-dev.sh` — add `uv pip install --python ~/.venv/bin/python -e` step
- `nixos-config/home-manager/home-agent-gogo.nix` — `ExecStartPre` on all
  three schedulers + Väinö's scheduler service unit (commit `9ad26b5`)
- `~/.config/systemd/user/pykoclaw-scheduler-vaino.service` — manual unit,
  already has `ExecStartPre` ✅
- Deployed NixOS config so Tyko + Pipsa services also have `ExecStartPre`

### Definition of Done

- [x] `install-dev.sh` installs pykoclaw + plugins into `~/.venv/` in editable mode
- [x] `~/.venv/bin/python -c "import pykoclaw"` succeeds after running `install-dev.sh`
- [x] Design settled: per-agent `requirements.txt` + `ExecStartPre` flock
- [x] Väinö's manual service unit has `ExecStartPre`
- [x] NixOS commit `9ad26b5` adds `ExecStartPre` to Tyko + Pipsa schedulers
      and adds Väinö's scheduler service to NixOS management
- [x] `home-manager switch` (or `nixos-rebuild switch`) deploys commit `9ad26b5`
- [x] Tyko and Pipsa services in `~/.config/systemd/user/` have `ExecStartPre`

### Must Have

- `install-dev.sh` installs all pykoclaw packages into `~/.venv/` in editable mode
- `ExecStartPre` on all three scheduler services for per-agent extra deps
- `flock` serialization to prevent concurrent `uv pip install` races
- Install target is always `~/.venv/bin/python`, not pykoclaw's tool venv
- `|| true` so a missing/empty `requirements.txt` never blocks service start

### Must NOT Have (Guardrails)

- No Nix/NixOS-specific code inside any pykoclaw Python package
- No new Python dependencies in `pyproject.toml`

---

## Deployment state (as of 2026-02-22)

| Service                    | Source             | Has `ExecStartPre`? |
| -------------------------- | ------------------ | ------------------- |
| `pykoclaw-scheduler-pipsa` | Nix (home-manager) | ✅ deployed         |
| `pykoclaw-scheduler-tyko`  | Nix (home-manager) | ✅ deployed         |
| `pykoclaw-scheduler-vaino` | Nix (home-manager) | ✅ deployed         |

After `home-manager switch` deploys commit `9ad26b5`, all three will be
Nix-managed and all three will have `ExecStartPre`. The manual Väinö service
file will be superseded by the Nix-managed one.

---

## TODOs

- [x] 1. Install pykoclaw + plugins into `~/.venv/` from `install-dev.sh`

  **What to do**:
  Add a `uv pip install --python ~/.venv/bin/python` step to `install-dev.sh`
  immediately after the existing `uv tool install` block:

  ```bash
  echo "Installing pykoclaw into ~/.venv/ for Claude Code skill access..."
  uv pip install --python ~/.venv/bin/python \
      -e ./pykoclaw \
      -e ./pykoclaw-messaging \
      -e ./pykoclaw-chat \
      -e ./pykoclaw-whatsapp \
      -e ./pykoclaw-acp \
      -e ./pykoclaw-matrix
  ```

  **File**: `install-dev.sh`

  **Acceptance Criteria**:
  - [x] `./install-dev.sh` completes without error
  - [x] `~/.venv/bin/python -c "import pykoclaw; print('OK')"` prints `OK`
  - [x] `~/.venv/bin/python -c "import pykoclaw_whatsapp; print('OK')"` prints `OK`
  - [x] Existing `uv tool install` step is unchanged

  **Commit**: YES
  - Message: `feat(install): install pykoclaw into ~/.venv/ for Claude Code skill access`
  - Files: `install-dev.sh`

---

- [x] 2. Deploy NixOS commit `9ad26b5` via `home-manager switch`

  **What to do**:
  Run `home-manager switch` (or `nixos-rebuild switch`) on the host to apply
  commit `9ad26b5` from `nixos-config`. This will:
  - Add `ExecStartPre` (flock + uv pip install) to `pykoclaw-scheduler-pipsa`
    and `pykoclaw-scheduler-tyko`
  - Add `pykoclaw-scheduler-vaino` as a Nix-managed service (superseding the
    manual unit)

  **Acceptance Criteria**:
  - [x] `systemctl --user cat pykoclaw-scheduler-pipsa` shows `ExecStartPre=`
  - [x] `systemctl --user cat pykoclaw-scheduler-tyko` shows `ExecStartPre=`
  - [x] `systemctl --user cat pykoclaw-scheduler-vaino` shows `ExecStartPre=`
  - [x] All three schedulers restart successfully after the switch

  **Commit**: N/A (infra deploy, not a code change)

---

## Commit Strategy

| After Task | Message                                                          | Files            | Verification                                           |
| ---------- | ---------------------------------------------------------------- | ---------------- | ------------------------------------------------------ |
| 1          | `feat(install): install pykoclaw into ~/.venv/ for skill access` | `install-dev.sh` | `~/.venv/bin/python -c "import pykoclaw; print('OK')"` |
| 2          | N/A — infra deploy                                               | systemd units    | `systemctl --user cat` each scheduler                  |

---

## Success Criteria

### Verification Commands

```bash
# Pykoclaw importable from ~/.venv/
~/.venv/bin/python -c "import pykoclaw; print('OK')"
~/.venv/bin/python -c "import pykoclaw_whatsapp; print('OK')"

# Confirm ExecStartPre is present in all three units
systemctl --user cat pykoclaw-scheduler-pipsa | grep ExecStartPre
systemctl --user cat pykoclaw-scheduler-tyko  | grep ExecStartPre
systemctl --user cat pykoclaw-scheduler-vaino | grep ExecStartPre

# Confirm extra agent runtime packages are installed
~/.venv/bin/python -c "import defusedxml, lxml; print('OK')"
```

### Final Checklist

- [x] `install-dev.sh` installs pykoclaw + plugins into `~/.venv/`
- [x] Skills can `import pykoclaw` successfully
- [x] Per-agent `requirements.txt` convention established
- [x] `ExecStartPre` flock pattern documented and implemented
- [x] Väinö's scheduler already works
- [x] NixOS config commit ready (`9ad26b5`)
- [x] Deployed — all three schedulers have `ExecStartPre`
