# Mitto ACP Web Client Setup

**Tags:** mitto, acp, tailscale, mobile
**Related:** [channel-dispatch.md]

## What Mitto is

Go-based ACP client with mobile-friendly WebUI. Connects to ACP agents
(like pykoclaw) over stdio and exposes a chat interface via HTTP.
Repo: https://github.com/inercia/mitto

## Build

Requires Go 1.25.5. On NixOS: `nix-shell -p go --run "cd ~/mitto && make build"`.
Binary goes to `~/.local/bin/mitto`.

## Key files

- `~/.mittorc` — main config (YAML): ACP servers, web settings, auth
- `~/.local/share/mitto/settings.json` — runtime settings (auto-managed)
- `~/.local/share/mitto/workspaces.json` — persisted workspaces (see gotchas)

## Config pattern for multiple pykoclaw instances

Each instance needs a wrapper script because Mitto splits commands with
naive whitespace splitting (no shell quoting support).

```sh
# ~/.local/bin/pykoclaw-ressu
#!/bin/sh
cd /home/agent/pipsa && exec /home/agent/pykoclaw/.venv/bin/pykoclaw acp
```

Each data directory has a `.env` with `PYKOCLAW_DATA=/path/to/dir` which
pykoclaw's Pydantic Settings picks up from CWD.

```yaml
# ~/.mittorc
acp:
  - pykoclaw:
      command: /home/agent/pykoclaw/.venv/bin/pykoclaw acp
  - ressu:
      command: /home/agent/.local/bin/pykoclaw-ressu
  - tyko:
      command: /home/agent/.local/bin/pykoclaw-tyko
```

## Workspaces

Workspaces bind an ACP server to a working directory. Persisted in
`workspaces.json`. Each needs `acp_command` explicitly — see gotchas.

## Network access via Tailscale Serve

Mitto binds to `127.0.0.1:8080` (local only). External access uses
`tailscale serve` which proxies over HTTPS with auto Let's Encrypt certs.

- Access URL: `https://gogo.crane-boa.ts.net/`
- Requires `tailscale set --operator=agent` (NixOS: `extraSetFlags`)
- Bare hostname `https://gogo/` won't work — cert is only for the FQDN

## NixOS integration (configuration-gogo.nix)

- `services.tailscale.extraSetFlags = ["--operator=agent"]`
- `services.tailscale.permitCertUid = "agent"`
- `systemd.services.mitto-web` — runs `mitto web` as agent user
- `systemd.services.tailscale-serve-mitto` — oneshot to configure the proxy

## Gotchas

1. **Command parsing bug**: `strings.Fields()` splits on whitespace, no
   shell quoting. `sh -c 'cd ... && ...'` breaks. Use wrapper scripts.
   (Issue filed: /tmp/mitto-issue.md)

2. **workspaces.json needs acp_command**: When loading persisted workspaces,
   Mitto doesn't resolve `acp_server` names to commands from `.mittorc`.
   You must manually include `acp_command` in `workspaces.json`.
   (Issue filed: /tmp/mitto-issue-workspaces.md)

3. **`--dir` flag is ephemeral**: Workspaces created via `--dir` aren't
   saved to `workspaces.json`. Don't use `--dir` for persistent setups —
   write `workspaces.json` directly and run `mitto web` without flags.

4. **CSRF on plain HTTP**: The external listener (`external_port`) sets
   `Secure` flag on CSRF cookies for non-localhost connections. Over plain
   HTTP (e.g. Tailscale IP), the browser silently drops the cookie and all
   POST/PUT requests fail. Fix: use `tailscale serve` for HTTPS.

5. **Both config files must agree on command path**: `settings.json`
   (`acp_servers[].command`) and `workspaces.json` (`acp_command`) must
   both point to the same pykoclaw binary. The workspace's `acp_command`
   is resolved from its `acp_server` name via `settings.json` only at
   session creation time (in `config_handlers.go`). Existing sessions keep
   whatever `acp_command` was persisted in `workspaces.json`.

6. **`install-dev.sh` binary path**: After `install-dev.sh`, the binary is
   at `~/.local/bin/pykoclaw` (uv tool install), NOT at
   `/home/agent/pykoclaw/.venv/bin/pykoclaw`. Mitto config must reference
   `~/.local/bin/pykoclaw` (or the absolute path
   `/home/agent/.local/bin/pykoclaw`). The `.venv` binary has stale code.

7. **Mitto reads config at startup only**: Changes to `settings.json` or
   `workspaces.json` require `systemctl --user restart mitto-web`. Already
   running sessions keep their old `acp_command` — you must create a new
   session (or manually edit `workspaces.json` and restart) to pick up
   a new binary path.

[channel-dispatch.md]: channel-dispatch.md
