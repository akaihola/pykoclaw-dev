# Memory Index

Cross-reference of all memory files in the Pykoclaw project.

## By topic

| File                             | Tags                                                 | Summary                                                                                    |
| -------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| [threading-model.md]             | whatsapp, sqlite, threading                          | WhatsApp plugin's 3-thread model and ThreadSafeConnection                                  |
| [neonize-quirks.md]              | whatsapp, neonize, gotcha                            | Neonize timestamp and JID pitfalls                                                         |
| [plugin-system.md]               | architecture, plugins                                | How plugins are discovered, loaded, and what they provide                                  |
| [channel-dispatch.md]            | messaging, architecture                              | How channel plugins route messages through dispatch_to_agent()                             |
| [workspace-layout.md]            | workspace, git, uv                                   | Multi-repo workspace structure and git boundaries                                          |
| [mitto-setup.md]                 | mitto, acp, tailscale, mobile                        | Mitto web client setup, config, Tailscale, and known gotchas                               |
| [acp-protocol-fix.md]            | acp, protocol, bugfix, mitto                         | ACP prompt response ordering + session resume → ClientPool fix                             |
| [acp-debugging.md]               | acp, mitto, debugging, claude-sdk                    | How to debug Mitto ↔ pykoclaw ↔ Claude CLI issues                                        |
| [asyncio-shutdown-gotcha.md]     | asyncio, gotcha, acp, mitto, zombie                  | asyncio.run() cleanup hangs forever — use manual loop                                      |
| [sdk-schema-gotcha.md]           | claude-sdk, mcp, tools, schema                       | Simple dict schemas make all fields required; use JSON Schema passthrough                  |
| [sqlite-migration-gotcha.md]     | sqlite, gotcha, migration, schema                    | CREATE TABLE IF NOT EXISTS never adds missing columns — need ALTER TABLE                   |
| [worktree-workflow.md]           | worktree, git, dev-workflow, multi-repo              | Feature worktree scripts + standard landing lifecycle (rebase→review→merge→deploy→cleanup) |
| [result-message-fallback.md]     | claude-sdk, agent-core, bugfix, gotcha               | ResultMessage.result text was silently dropped → empty replies                             |
| [debugging-workflow.md]          | debugging, workflow, gotcha, acp, whatsapp           | Ask which channel first; two SDK loops; verify imports                                     |
| [anyio-cancel-scope-leak.md]     | acp, anyio, asyncio, cancel-scope, resolved          | anyio cancel scope leak — resolved via process-isolated workers                            |
| [process-isolated-workers.md]    | acp, architecture, worker, process-isolation         | SDK workers run in subprocess isolation from ACP server                                    |
| [tool-use-text-concatenation.md] | sdk-consume, streaming, bugfix, mitto, gotcha        | Text around hidden tool calls concatenated without separator                               |
| [matrix-nio-gotchas.md]          | matrix, matrix-nio, gotcha, e2ee                     | matrix-nio is_group, timestamps, logging, E2EE, cross-signing, typing indicators           |
| [plugin-config-env-file.md]      | config, gotcha, pydantic-settings, env               | Plugin .env hardcodes default path; must resolve from PYKOCLAW_DATA                        |
| [session-resume-retry.md]        | claude-sdk, dispatch, scheduler, gotcha               | Auto-retry on ProcessError in dispatch + scheduler; stale prompt hash detection            |
| [matrix-agent-reply-storage.md]  | matrix, bugfix, gotcha, session-resume, context-loss | Agent replies not stored locally → context lost on session resume failure                  |
| [multi-agent-routing.md]         | whatsapp, routing, multi-agent, architecture         | WhatsApp multi-agent group routing: config, per-agent DB, delivery polling                 |
| [bananas-delivery-bug.md]        | scheduler, delivery, whatsapp, routing, bug-fix      | Bare target_conversation causes deliveries stuck as pending with channel_prefix='chat'     |

## By tag

| Tag          | Files                                                                                                                                                                   |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| acp          | [mitto-setup.md], [acp-protocol-fix.md], [acp-debugging.md], [asyncio-shutdown-gotcha.md], [anyio-cancel-scope-leak.md], [process-isolated-workers.md]                  |
| agent-core   | [result-message-fallback.md]                                                                                                                                            |
| bugfix       | [acp-protocol-fix.md], [result-message-fallback.md], [tool-use-text-concatenation.md]                                                                                   |
| claude-sdk   | [acp-protocol-fix.md], [acp-debugging.md], [sdk-schema-gotcha.md], [result-message-fallback.md]                                                                         |
| debugging    | [acp-debugging.md], [debugging-workflow.md]                                                                                                                             |
| architecture | [plugin-system.md], [channel-dispatch.md], [process-isolated-workers.md], [multi-agent-routing.md]                                                                      |
| dev-workflow | [worktree-workflow.md]                                                                                                                                                  |
| git          | [workspace-layout.md], [worktree-workflow.md]                                                                                                                           |
| anyio        | [anyio-cancel-scope-leak.md]                                                                                                                                            |
| asyncio      | [asyncio-shutdown-gotcha.md], [anyio-cancel-scope-leak.md]                                                                                                              |
| gotcha       | [neonize-quirks.md], [sqlite-migration-gotcha.md], [asyncio-shutdown-gotcha.md], [tool-use-text-concatenation.md], [matrix-nio-gotchas.md], [plugin-config-env-file.md] |
| messaging    | [channel-dispatch.md]                                                                                                                                                   |
| mitto        | [mitto-setup.md], [acp-protocol-fix.md], [acp-debugging.md], [asyncio-shutdown-gotcha.md], [tool-use-text-concatenation.md]                                             |
| zombie       | [asyncio-shutdown-gotcha.md]                                                                                                                                            |
| mobile       | [mitto-setup.md]                                                                                                                                                        |
| neonize      | [neonize-quirks.md]                                                                                                                                                     |
| plugins      | [plugin-system.md]                                                                                                                                                      |
| migration    | [sqlite-migration-gotcha.md]                                                                                                                                            |
| schema       | [sdk-schema-gotcha.md], [sqlite-migration-gotcha.md]                                                                                                                    |
| sqlite       | [threading-model.md], [sqlite-migration-gotcha.md]                                                                                                                      |
| tailscale    | [mitto-setup.md]                                                                                                                                                        |
| threading    | [threading-model.md]                                                                                                                                                    |
| uv           | [workspace-layout.md]                                                                                                                                                   |
| whatsapp     | [threading-model.md], [neonize-quirks.md], [multi-agent-routing.md]                                                                                                     |
| multi-agent  | [multi-agent-routing.md]                                                                                                                                                |
| routing      | [multi-agent-routing.md]                                                                                                                                                |
| protocol     | [acp-protocol-fix.md]                                                                                                                                                   |
| worktree     | [worktree-workflow.md]                                                                                                                                                  |
| workspace    | [workspace-layout.md]                                                                                                                                                   |
| multi-repo   | [worktree-workflow.md]                                                                                                                                                  |
| mcp          | [sdk-schema-gotcha.md]                                                                                                                                                  |

| channel-plugins | [matrix-agent-reply-storage.md] |
| context-loss | [matrix-agent-reply-storage.md] |
| config | [plugin-config-env-file.md] |
| cross-signing | [matrix-nio-gotchas.md] |
| dispatch | [session-resume-retry.md] |
| scheduler | [session-resume-retry.md], [bananas-delivery-bug.md] |
| e2ee | [matrix-nio-gotchas.md] |
| env | [plugin-config-env-file.md] |
| matrix | [matrix-nio-gotchas.md] |
| matrix-nio | [matrix-nio-gotchas.md] |
| pydantic-settings | [plugin-config-env-file.md] |
| tools | [sdk-schema-gotcha.md] |

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
[debugging-workflow.md]: debugging-workflow.md
[result-message-fallback.md]: result-message-fallback.md
[worktree-workflow.md]: worktree-workflow.md
[anyio-cancel-scope-leak.md]: anyio-cancel-scope-leak.md
[process-isolated-workers.md]: process-isolated-workers.md
[tool-use-text-concatenation.md]: tool-use-text-concatenation.md
[matrix-nio-gotchas.md]: matrix-nio-gotchas.md
[plugin-config-env-file.md]: plugin-config-env-file.md

| session-resume | [matrix-agent-reply-storage.md] |

[matrix-agent-reply-storage.md]: matrix-agent-reply-storage.md
[bananas-delivery-bug.md]: bananas-delivery-bug.md
[multi-agent-routing.md]: multi-agent-routing.md
[session-resume-retry.md]: session-resume-retry.md
