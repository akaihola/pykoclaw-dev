# Sandbox Plugin — Harness-Agnostic Agent Sandboxing

## Status: Backlog

## Priority: 8

## TL;DR

> **Quick Summary**: Add a `pykoclaw-sandbox` plugin that provides OS-level
> filesystem and network isolation for **all** agent subprocesses — channel
> gateways (WhatsApp, Matrix, Slack), the scheduler, the chat REPL, and ACP
> workers. Uses Landlock (filesystem) + bubblewrap network namespace +
> domain-filtering proxy. Requires one small core change: a unified
> `get_agent_sandbox()` hook called from the two execution chokepoints
> (`query_agent()` and `WorkerPool._spawn_worker()`). All sandbox logic
> lives in the plugin.
>
> **Estimated Effort**: Medium
> **Depends On**: (none)

---

## Motivation

Every agent subprocess runs Claude Code with `permission_mode="bypassPermissions"`.
That means the harness executes arbitrary bash commands, file reads/writes, and
network requests on the host with zero application-level enforcement. Today
security relies entirely on trust in the message sender.

The threat is not limited to ACP workers. Channel gateways use `query_agent()`
with the same `bypassPermissions` flag — a user asking through WhatsApp, Matrix,
or Slack to "read ~/.ssh/id_rsa" or "exfiltrate ~/pykoclaw/.env" will be served.
The Bash tool makes this worse: arbitrary shell commands inherit the same
unrestricted environment.

A sandbox plugin provides **uniform OS-level enforcement** at the kernel level,
independent of which harness is inside and which channel the user arrived from.
Crucially, Landlock restrictions and the network namespace are inherited by all
descendant processes, including every shell command the agent runs via the Bash
tool — there is no application-level bypass.

See also: `~/my-knowledge/pages/Projects/Sandbox harness-agnostic agent sandboxing.md`
for full research (Nix wrappers survey, Landlock vs bwrap comparison, tier analysis).

## Architecture: two chokepoints, one hook

### The two execution paths

Every agent subprocess in the codebase goes through exactly one of two functions:

| Path            | Function                                        | What uses it                                                                                                             |
| --------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Conversational  | `query_agent()` in `pykoclaw/agent_core.py`     | WhatsApp, Matrix, Slack, chat REPL, scheduler — and any future gateway that follows the `dispatch_to_agent()` convention |
| ACP worker pool | `WorkerPool._spawn_worker()` in `pykoclaw-acp/` | ACP sessions                                                                                                             |

A single plugin hook (`get_agent_sandbox()`) is called from both. Future gateway
plugins that use `dispatch_to_agent()` → `query_agent()` are automatically
sandboxed with no additional work.

### Core change: one new plugin hook

Rename the planned `get_worker_sandbox()` to `get_agent_sandbox()` and call it
from both chokepoints:

```python
# pykoclaw/src/pykoclaw/plugins.py

@dataclass
class AgentSandbox:
    cmd_prefix: list[str]           # bwrap wrapper args (Layer 2)
    pre_exec: str | None            # "module:function" ref for Landlock (Layer 1)
    env: dict[str, str]             # extra env vars, e.g. HTTP_PROXY (Layer 3)

class PykoClawPlugin(Protocol):
    # existing hooks...
    def get_agent_sandbox(self, workspace: Path) -> AgentSandbox | None: ...

class PykoClawPluginBase:
    # existing defaults...
    def get_agent_sandbox(self, workspace: Path) -> AgentSandbox | None:
        return None
```

### Core integration: three callsites

**1. `query_agent()` (`agent_core.py`)** — applies `pre_exec` (Landlock) + `env`:

```python
# After conv_dir is established, before ClaudeAgentOptions:
sandbox = _collect_sandbox(plugins, conv_dir)   # calls get_agent_sandbox()
if sandbox and sandbox.pre_exec:
    # Serialize for use inside the subprocess (worker.py pattern)
    sandbox_pre_exec = sandbox.pre_exec
else:
    sandbox_pre_exec = None

options = ClaudeAgentOptions(
    ...
    env={"SHELL": "/bin/bash", **(sandbox.env if sandbox else {})},
)
# bwrap cmd_prefix: ClaudeAgentOptions has no cmd_prefix today — see Open Decisions
```

**2. `WorkerPool._spawn_worker()` (`worker_pool.py`)** — applies `cmd_prefix` + `env`:

```python
sandbox = self._sandbox  # collected from plugins at init via get_agent_sandbox(workspace)
if sandbox:
    cmd = [*sandbox.cmd_prefix, *self._worker_cmd]
    env = {**os.environ, **sandbox.env}
else:
    cmd = self._worker_cmd
    env = None

process = await asyncio.create_subprocess_exec(
    *cmd, stdin=PIPE, stdout=PIPE, stderr=PIPE, env=env,
)
```

**3. `worker.py`** — applies `pre_exec` (Landlock) inside the worker process:

```python
if config.sandbox_pre_exec:
    module, func = config.sandbox_pre_exec.rsplit(":", 1)
    pre_exec_fn = getattr(importlib.import_module(module), func)
    pre_exec_fn(Path(config.cwd))
```

### Plugin: `pykoclaw-sandbox`

All sandbox logic lives here — core knows nothing about Landlock or bwrap:

```
pykoclaw-sandbox/
├── pyproject.toml              # entry point: sandbox = "pykoclaw_sandbox:SandboxPlugin"
└── src/pykoclaw_sandbox/
    ├── __init__.py             # SandboxPlugin class
    ├── config.py               # SandboxSettings (PYKOCLAW_SANDBOX_*)
    ├── landlock_setup.py       # apply_landlock(workspace) — Layer 1
    ├── bwrap.py                # build_bwrap_cmd(workspace) — Layer 2
    └── proxy.py                # domain-filtering proxy — Layer 3
```

```python
# __init__.py
class SandboxPlugin(PykoClawPluginBase):
    def get_agent_sandbox(self, workspace: Path) -> AgentSandbox:
        config = get_config()
        return AgentSandbox(
            cmd_prefix=build_bwrap_cmd(workspace, config) if config.bwrap_enabled else [],
            pre_exec="pykoclaw_sandbox.landlock_setup:apply_landlock" if config.landlock_enabled else None,
            env=_proxy_env(config) if config.proxy_enabled else {},
        )

    def register_commands(self, group):
        # pykoclaw sandbox status  — show current sandbox config
        # pykoclaw sandbox proxy   — run domain-filtering proxy
        # pykoclaw sandbox test    — verify isolation works
        ...

    def get_config_class(self):
        return SandboxSettings
```

### Configuration

```bash
# .env
PYKOCLAW_SANDBOX_ENABLED=true
PYKOCLAW_SANDBOX_LANDLOCK=true          # Layer 1: filesystem
PYKOCLAW_SANDBOX_BWRAP=true             # Layer 2: network namespace
PYKOCLAW_SANDBOX_PROXY=true             # Layer 3: domain filtering
PYKOCLAW_SANDBOX_ALLOWED_DOMAINS=api.anthropic.com,localhost
PYKOCLAW_SANDBOX_PROXY_SOCKET=/tmp/pykoclaw-sandbox-proxy.sock
```

### Layer-by-layer breakdown

| Layer                        | What                                      | Where                                                        | Plugin or core?     |
| ---------------------------- | ----------------------------------------- | ------------------------------------------------------------ | ------------------- |
| 1 — Landlock                 | Filesystem allow-only                     | `landlock_setup.py`, called via `pre_exec` ref               | **Plugin**          |
| 2 — bwrap                    | Network namespace isolation               | `bwrap.py`, returned as `cmd_prefix`                         | **Plugin**          |
| 3 — Proxy                    | Domain-level network filter               | `proxy.py`, UNIX socket path in `env`                        | **Plugin**          |
| 4 — systemd                  | Service-level hardening                   | nixos-config                                                 | **Neither** (infra) |
| hook — `get_agent_sandbox()` | Glue: connects plugin to both chokepoints | `plugins.py`, `agent_core.py`, `worker_pool.py`, `worker.py` | **Core** (minimal)  |

### What changes in core

**4 files** touched, all small additions:

1. **`pykoclaw/src/pykoclaw/plugins.py`** — rename `WorkerSandbox` → `AgentSandbox`, rename hook to `get_agent_sandbox()`, no-op default in base class (~15 lines)
2. **`pykoclaw/src/pykoclaw/agent_core.py`** — collect sandbox from plugins, apply `pre_exec` + `env` in `query_agent()` (~10 lines)
3. **`pykoclaw-acp/src/pykoclaw_acp/worker_pool.py`** — collect sandbox from plugins, prepend `cmd_prefix`, pass `env` (~10 lines)
4. **`pykoclaw-acp/src/pykoclaw_acp/worker.py`** — call `pre_exec` if present in config (~5 lines)
5. **`pykoclaw-acp/src/pykoclaw_acp/worker_protocol.py`** — add `sandbox_pre_exec: str | None` to `WorkerConfig` (~1 line)

Total core diff: ~40 lines. All sandbox logic (~200+ lines) lives in the plugin.

## Network sandboxing design

### Why a proxy is required for domain filtering

`bwrap --unshare-net` creates a network namespace with only loopback — no
internet routing at all. Domain-based filtering cannot be done at the kernel
level (Landlock TCP in Linux 6.2+ restricts by port number, not domain/IP).
The filtering proxy is therefore not optional if domain granularity is wanted;
it is the _only_ egress point.

### How domain filtering works (no MITM/decryption)

For HTTPS, the domain name appears in plaintext in the TLS `ClientHello` SNI
field and in the HTTP `CONNECT` request, before any encryption. The proxy
intercepts `CONNECT api.anthropic.com:443` and checks the hostname against the
allowlist — no certificate needed, no traffic decryption.

```
sandbox netns (bwrap --unshare-net)
  Claude Code / bash subprocess
    ↓ HTTPS_PROXY=http+unix:///tmp/sandbox-proxy.sock
  UNIX socket (bind-mounted from host via bwrap --bind)
    ↓
  [host] pykoclaw-sandbox proxy process
    checks: is api.anthropic.com in allowlist?
    → YES: opens real TCP connection, tunnels bytes
    → NO: returns 407 / closes connection
```

Programs that set `--noproxy` or make raw `connect()` syscalls cannot reach the
internet at all because there is no route in the namespace — they get
"Network unreachable". This is the correct failure mode: unknown programs fail
closed, not open.

### CCM proxy (localhost:13456)

Claude Code's own permission layer uses an internal proxy at `localhost:13456`.
Inside `--unshare-net`, that address is unreachable (the namespace has its own
loopback). **Resolution**: bind-mount the CCM UNIX socket into the namespace,
just like the filtering proxy socket. Both are exposed consistently as
bind-mounted UNIX sockets; no routing changes needed.

```bash
bwrap \
  --unshare-net \
  --bind /tmp/pykoclaw-sandbox-proxy.sock /tmp/pykoclaw-sandbox-proxy.sock \
  --bind /tmp/claude-ccm.sock             /tmp/claude-ccm.sock \
  ...
```

### Bash tool inheritance

Landlock `restrict_self()` and the bwrap network namespace both apply to the
entire process tree. Every shell command run by the agent via the Bash tool
inherits the same restrictions — there is no application-level bypass path.
A bash subprocess calling `cat ~/.ssh/id_rsa` hits the same Landlock block as
the agent's own `Read` tool call.

## What changes in core

Only **5 file edits** (4 files + 1 new dataclass rename), all small additions.
Total core diff: ~40 lines. All sandbox logic (~200+ lines) lives in the plugin.

## Implementation order

1. **Core hook** — rename/add `AgentSandbox` dataclass + `get_agent_sandbox()` to plugin protocol
2. **Plugin skeleton** — `pykoclaw-sandbox` package with config + no-op
3. **Layer 1 (Landlock)** — `landlock_setup.py`; wire into `agent_core.py` + `worker.py`; test with a gateway message asking for `~/.ssh/id_rsa`
4. **Layer 2 (bwrap)** — `bwrap.py` with `--unshare-net` + UNIX socket bind-mounts for CCM and proxy; wire into `worker_pool.py`
5. **Layer 3 (proxy)** — `proxy.py` domain-filtering proxy; wire HTTPS_PROXY env into both chokepoints; test network exfiltration attempt
6. **Layer 4 (systemd)** — nixos-config service hardening, independent of plugin

## Open decisions

- [x] `pre_exec` serialization: **module:function string** — worker doesn't load plugins, so the function reference is passed as a string and resolved with `importlib` at call time.
- [x] bwrap + CCM proxy: **bind-mount both sockets** (`--bind /tmp/claude-ccm.sock /tmp/claude-ccm.sock` and similarly for the filtering proxy socket). No routing changes required.
- [ ] `bwrap cmd_prefix` for `query_agent()`: `ClaudeAgentOptions` has no `cmd_prefix` today. Options: (a) add `cmd_prefix` to `ClaudeAgentOptions` upstream; (b) wrap the `cli_path` binary in a shell wrapper that prepends bwrap args; (c) set `cli_path` to a generated wrapper script per session. Option (a) is cleanest — worth a small upstream PR to `claude-agent-sdk`.
- [ ] Should `get_agent_sandbox()` receive the conversation name in addition to workspace? Would allow per-conversation sandbox policies, but adds complexity. Defer unless needed.
- [ ] Landlock fail mode: fail-open (log warning, continue unsandboxed) or fail-closed (refuse to start subprocess)? Lean fail-closed for production, fail-open with loud warning for dev.
- [ ] Nested sandbox conflict: if Claude Code's own `/sandbox` also tries bwrap inside our bwrap, nested user namespaces may be needed (`--new-session` + `--die-with-parent`). Test empirically.

## Related

- [scheduler-relative-time.md] — also a pykoclaw improvement discovered in the same session
- `~/my-knowledge/pages/Projects/Sandbox harness-agnostic agent sandboxing.md` — full research + comparison tables

[scheduler-relative-time.md]: scheduler-relative-time.md
