# Systemd Services with Playwright on NixOS

**Tags:** nixos, systemd, playwright, gotcha, deployment
**Related:** [matrix-nio-gotchas.md]

## Problem

Python `playwright` finds browsers via `$PLAYWRIGHT_BROWSERS_PATH`. On NixOS,
this is set by the user's shell profile — but systemd services start with a
clean environment and don't have it.

## Failed approaches

1. **Hardcode nix store path** in service `Environment=` — breaks on rebuilds.
2. **`nix-shell -p playwright-driver.browsers --run ...`** — does NOT export
   `PLAYWRIGHT_BROWSERS_PATH`. The var appeared to work in testing only because
   the interactive shell already had it. `nix-shell` just passed it through.
3. **NixOS detection in Python** (nix-build, nix-env calls) — violates
   platform-agnostic package rule.
4. **`playwright install`** — downloads non-nix binaries that fail with
   `libnspr4.so` missing (no NixOS dynamic linker patching).

## Working solution

Resolve dynamically at service startup via `nix-build`:

```ini
ExecStart=/bin/sh -c '\
  export PLAYWRIGHT_BROWSERS_PATH="$(/run/current-system/sw/bin/nix-build "<nixpkgs>" -A playwright-driver.browsers --no-out-link 2>/dev/null)" \
  && exec /home/agent/.venv/bin/pykoclaw matrix run'
```

## Verification

Always check the running process env, not your shell:

```bash
PID=$(systemctl --user show pykoclaw-matrix -p MainPID --value)
cat /proc/$PID/environ | tr '\0' '\n' | rg PLAYWRIGHT
```

[matrix-nio-gotchas.md]: matrix-nio-gotchas.md
