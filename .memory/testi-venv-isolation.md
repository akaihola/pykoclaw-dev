# Testi Instance Isolation: ~/.testi-venv and ~/.testi-mitto

**Tags:** testi, deployment, venv, mitto, isolation
**Related:** [mitto-setup.md], [worktree-workflow.md]

## The problem

Before this was set up, all testi services shared `~/.venv` with production.
Deploying a feature branch to test in testi would have affected all instances.

## The solution

Testi has its own virtualenv and mitto data directory:

| Resource         | Production                 | Testi                            |
| ---------------- | -------------------------- | -------------------------------- |
| Python venv      | `~/.venv`                  | `~/.testi-venv`                  |
| Mitto data dir   | `~/.local/share/mitto`     | `~/.testi-mitto`                 |
| Mitto ACP server | `"pykoclaw"`               | `"testi"`                        |
| ACP binary       | `~/.venv/bin/pykoclaw acp` | `~/.testi-venv/bin/pykoclaw acp` |

## Deployment

```bash
# Deploy main branch to testi
./install-testi.sh

# Deploy a feature worktree to testi
./install-testi.sh streaming-responses
```

`install-testi.sh` installs editable packages into `~/.testi-venv` and
restarts only the testi services (pykoclaw-scheduler-testi,
pykoclaw-matrix-testi, mitto-web-testi). Production is untouched.

## `MITTO_DIR` env var

Mitto uses `MITTO_DIR` to locate its data directory (settings, workspaces,
sessions). `mitto-web-testi.service` sets `MITTO_DIR=/home/agent/.testi-mitto`.
The `~/.testi-mitto/settings.json` defines the `"testi"` ACP server pointing
at `~/.testi-venv/bin/pykoclaw acp`.

## Known limitation: ~/.mittorc is always loaded

Mitto always loads `~/.mittorc` from `$HOME` regardless of `MITTO_DIR`. This
means `mitto-web-testi` shows all production ACP servers (auggie, pykoclaw,
ressu, tyko) alongside `testi` in the server picker. **Always select `testi`
explicitly** when using the testi Mitto instance. Do not waste time trying to
suppress `~/.mittorc` — there is no env var for it and the `--config` flag
path is complex.

## NixOS service files

Testi service `ExecStart` lines are in `home-manager/home-agent-gogo.nix`.
They use `%h/.testi-venv/bin/pykoclaw`. To change them, edit that file,
commit, and run the rebuild script (see CLAUDE.md "NixOS home-manager rebuild").

[mitto-setup.md]: mitto-setup.md
[worktree-workflow.md]: worktree-workflow.md
