# Memory Index

Cross-reference of all memory files in the Pykoclaw project.

## By topic

| File                  | Tags                        | Summary                                                        |
| --------------------- | --------------------------- | -------------------------------------------------------------- |
| [threading-model.md]  | whatsapp, sqlite, threading | WhatsApp plugin's 3-thread model and ThreadSafeConnection      |
| [neonize-quirks.md]   | whatsapp, neonize, gotcha   | Neonize timestamp and JID pitfalls                             |
| [plugin-system.md]    | architecture, plugins       | How plugins are discovered, loaded, and what they provide      |
| [channel-dispatch.md] | messaging, architecture     | How channel plugins route messages through dispatch_to_agent() |
| [workspace-layout.md] | workspace, git, uv          | Multi-repo workspace structure and git boundaries              |
| [mitto-setup.md]      | mitto, acp, tailscale, mobile | Mitto web client setup, config, Tailscale, and known gotchas |
| [acp-protocol-fix.md] | acp, protocol, bugfix, mitto  | ACP prompt response ordering + session resume → ClientPool fix |
| [acp-debugging.md]    | acp, mitto, debugging, claude-sdk | How to debug Mitto ↔ pykoclaw ↔ Claude CLI issues      |
| [asyncio-shutdown-gotcha.md] | asyncio, gotcha, acp, mitto, zombie | asyncio.run() cleanup hangs forever — use manual loop |
| [sdk-schema-gotcha.md] | claude-sdk, mcp, tools, schema    | Simple dict schemas make all fields required; use JSON Schema passthrough |
| [sqlite-migration-gotcha.md] | sqlite, gotcha, migration, schema | CREATE TABLE IF NOT EXISTS never adds missing columns — need ALTER TABLE |
| [worktree-workflow.md] | worktree, git, dev-workflow, multi-repo | Feature worktree scripts for cross-repo development |

## By tag

| Tag          | Files                                     |
| ------------ | ----------------------------------------- |
| acp          | [mitto-setup.md], [acp-protocol-fix.md], [acp-debugging.md], [asyncio-shutdown-gotcha.md] |
| bugfix       | [acp-protocol-fix.md]                     |
| claude-sdk   | [acp-protocol-fix.md], [acp-debugging.md], [sdk-schema-gotcha.md] |
| debugging    | [acp-debugging.md]                        |
| architecture | [plugin-system.md], [channel-dispatch.md] |
| dev-workflow | [worktree-workflow.md]                    |
| git          | [workspace-layout.md], [worktree-workflow.md] |
| asyncio      | [asyncio-shutdown-gotcha.md]                      |
| gotcha       | [neonize-quirks.md], [sqlite-migration-gotcha.md], [asyncio-shutdown-gotcha.md] |
| messaging    | [channel-dispatch.md]                     |
| mitto        | [mitto-setup.md], [acp-protocol-fix.md], [acp-debugging.md], [asyncio-shutdown-gotcha.md] |
| zombie       | [asyncio-shutdown-gotcha.md]                      |
| mobile       | [mitto-setup.md]                          |
| neonize      | [neonize-quirks.md]                       |
| plugins      | [plugin-system.md]                        |
| migration    | [sqlite-migration-gotcha.md]              |
| schema       | [sdk-schema-gotcha.md], [sqlite-migration-gotcha.md] |
| sqlite       | [threading-model.md], [sqlite-migration-gotcha.md] |
| tailscale    | [mitto-setup.md]                          |
| threading    | [threading-model.md]                      |
| uv           | [workspace-layout.md]                     |
| whatsapp     | [threading-model.md], [neonize-quirks.md] |
| protocol     | [acp-protocol-fix.md]                     |
| worktree     | [worktree-workflow.md]                    |
| workspace    | [workspace-layout.md]                     |
| multi-repo   | [worktree-workflow.md]                    |
| mcp          | [sdk-schema-gotcha.md]                    |

| tools        | [sdk-schema-gotcha.md]                    |

[acp-debugging.md]: acp-debugging.md
[acp-protocol-fix.md]: acp-protocol-fix.md
[asyncio-shutdown-gotcha.md]: asyncio-shutdown-gotcha.md
[threading-model.md]: threading-model.md
[neonize-quirks.md]: neonize-quirks.md
[plugin-system.md]: plugin-system.md
[channel-dispatch.md]: channel-dispatch.md
[workspace-layout.md]: workspace-layout.md
[mitto-setup.md]: mitto-setup.md
[sdk-schema-gotcha.md]: sdk-schema-gotcha.md
[sqlite-migration-gotcha.md]: sqlite-migration-gotcha.md
[worktree-workflow.md]: worktree-workflow.md
