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

## By tag

| Tag          | Files                                     |
| ------------ | ----------------------------------------- |
| architecture | [plugin-system.md], [channel-dispatch.md] |
| git          | [workspace-layout.md]                     |
| gotcha       | [neonize-quirks.md]                       |
| messaging    | [channel-dispatch.md]                     |
| neonize      | [neonize-quirks.md]                       |
| plugins      | [plugin-system.md]                        |
| sqlite       | [threading-model.md]                      |
| threading    | [threading-model.md]                      |
| uv           | [workspace-layout.md]                     |
| whatsapp     | [threading-model.md], [neonize-quirks.md] |
| workspace    | [workspace-layout.md]                     |

[threading-model.md]: threading-model.md
[neonize-quirks.md]: neonize-quirks.md
[plugin-system.md]: plugin-system.md
[channel-dispatch.md]: channel-dispatch.md
[workspace-layout.md]: workspace-layout.md
