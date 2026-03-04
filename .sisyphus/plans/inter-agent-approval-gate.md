# Inter-Agent Approval Gate

## Status: Backlog

## Priority: 25

## TL;DR

> **Quick Summary**: Human-approved messaging between independent pykoclaw agents, presented as a dedicated ACP conversation in Mitto
> **Estimated Effort**: Medium-Large
> **Depends On**: —

## Context

Running multiple pykoclaw agents with different exposure levels creates an inter-agent communication problem. Agents need to share information (e.g., "fiscal year ends March 31, set a reminder"), but unrestricted messaging risks leaking sensitive data from private agents (finance/business) into semi-public ones (Tyko, demoed in group chats).

No existing framework (A2A, AutoGen, LangGraph, CrewAI) provides human-gated messaging between **independent autonomous agents**. They all handle human-in-the-loop within a single orchestrated workflow.

### Threat model driving this

```
Tyko:    semi-public (demoed in Matrix/Telegram/WhatsApp groups, autonomous messaging)
Finance: private (manual approval, close monitoring, never in group chats)
Väinö:   external stakeholder (Päivi's data)
Coleaders: external stakeholder (team data)
```

Information must not flow between agents without explicit human approval. The human may also **edit** the message before forwarding (redact amounts, simplify, etc.).

## Design

### Core idea: Approval gate as a dedicated ACP server

A lightweight, **non-LLM** ACP-compatible server that:
1. Reads pending approval requests from a shared queue database
2. Presents each request as a conversation message in Mitto
3. Interprets the user's response deterministically
4. Delivers approved (possibly edited) messages to the target agent

In Mitto, it appears as a regular conversation — a dedicated "Approvals" inbox.

### UX: Leveraging Mitto's existing question detection

Mitto auto-detects questions and renders response buttons. The gate formats each approval request so Mitto shows three buttons:

```
┌─────────────────────────────────────────────────────┐
│  📨 Message from Finance → Tyko                     │
│                                                     │
│  "Atomikettu Oy fiscal year ends March 31.          │
│   Please set a reminder for late February."          │
│                                                     │
│  Accept, reject, or edit this message?               │
│                                                     │
│  [Accept]  [Reject]  [Edit]                          │
└─────────────────────────────────────────────────────┘
```

Button mapping (case-insensitive):
- **"Accept"** → prefills `yes` → gate delivers message unmodified
- **"Reject"** → prefills `no` → gate discards message
- **"Edit"** → prefills the full original message text → user modifies in input box → gate delivers the modified version

**No Mitto changes needed.** This is pure ACP server behavior.

### Architecture

```
                    ┌──────────────────┐
                    │   pykoclaw-gate  │
                    │   ACP server     │
                    │  (no LLM needed) │
                    └────────┬─────────┘
                             │ reads/writes
                    ┌────────▼─────────┐
                    │   gate.db        │
                    │  (shared queue)  │
                    │  ~/.local/share/ │
                    │  pykoclaw/       │
                    └──┬───────────┬───┘
           writes ↑    │           │    ↓ reads
    ┌──────────────┐   │           │   ┌──────────────────┐
    │  Agent A      │   │           │   │  Target workspace │
    │  MCP tool:    │   │           │   │  .gate-inbox/     │
    │  send_to_agent│───┘           └──▶│  <msg>.md         │
    └──────────────┘                    └──────────────────┘
```

### Components

#### 1. Plugin: `pykoclaw-gate`

New pykoclaw package providing:

```
pykoclaw-gate/
└── src/pykoclaw_gate/
    ├── __init__.py     # GatePlugin(PykoClawPluginBase)
    ├── db.py           # Approval queue schema + operations
    ├── tools.py        # MCP tool definition: send_to_agent
    ├── server.py       # Lightweight ACP server (deterministic, no LLM)
    ├── delivery.py     # Post-approval delivery to target workspace
    └── config.py       # Policy configuration (GateSettings)
```

**Plugin registration** via entry point:
```toml
[project.entry-points."pykoclaw.plugins"]
gate = "pykoclaw_gate:GatePlugin"
```

Installed in every agent workspace that should be able to send cross-agent messages.

#### 2. MCP tool: `send_to_agent`

Provided by the gate plugin to agent SDK sessions:

```json
{
  "name": "send_to_agent",
  "description": "Send a message to another agent. Requires human approval before delivery.",
  "parameters": {
    "target_agent": "Name of the target agent (e.g., 'tyko', 'finance')",
    "message": "The message to send",
    "context": "Optional: why this message is being sent (shown to human for approval context)"
  }
}
```

Writes to shared `gate.db`:
```sql
CREATE TABLE approval_queue (
    id TEXT PRIMARY KEY,
    sender_agent TEXT NOT NULL,
    target_agent TEXT NOT NULL,
    message TEXT NOT NULL,
    context TEXT,              -- why the agent wants to send this
    status TEXT DEFAULT 'pending',  -- pending, approved, rejected, delivered
    original_message TEXT,     -- preserved if user edits
    approved_message TEXT,     -- what actually gets delivered (may differ from original)
    created_at TEXT NOT NULL,
    decided_at TEXT,
    delivered_at TEXT
);
```

#### 3. ACP approval server

Lightweight process speaking ACP protocol. **No LLM needed** — purely deterministic:

1. On Mitto connection: check `approval_queue` for `status = 'pending'`
2. Present oldest pending as assistant message with question format
3. Parse user response:
   - `yes` / `y` / `ok` / `accept` (case-insensitive) → mark approved, deliver original
   - `no` / `n` / `reject` (case-insensitive) → mark rejected
   - Any other text → mark approved, store as `approved_message`, deliver edited version
4. Present next pending, or confirm "No pending approvals"

Runs as systemd service: `pykoclaw-gate` (or integrated into an existing service).

#### 4. Post-approval delivery

After approval, deliver to target workspace. **v1: file-based inbox.**

Write to `<target_workspace>/.gate-inbox/<timestamp>-<sender>.md`:
```markdown
---
from: finance
date: 2026-02-26T14:30:00+02:00
approved: 2026-02-26T14:35:00+02:00
edited: false
---

Atomikettu Oy fiscal year ends March 31. Please set a reminder for late February.
```

Target agent's `CLAUDE.md` includes:
```
## Inter-agent inbox
Check `.gate-inbox/` for messages from other agents. Process and acknowledge them,
then move to `.gate-inbox/processed/`.
```

### Policy configuration

`~/.config/pykoclaw/gate-policy.json`:
```json
{
  "default": "require_approval",
  "agents": {
    "tyko": { "workspace": "~/my-knowledge" },
    "finance": { "workspace": "~/finance" },
    "ressu": { "workspace": "~/pipsa" },
    "vaino": { "workspace": "~/paivi" },
    "coleaders": { "workspace": "~/coleaders" }
  },
  "policies": {
    "tyko→ressu": "auto",
    "ressu→tyko": "auto"
  }
}
```

Policies: `require_approval` (default), `auto` (trusted pair), `block` (never allow).

### What requires NO core changes (v1)

Everything above is pure plugin + separate process:
- Plugin provides MCP tool → agents can `send_to_agent`
- Shared SQLite DB → decouples sender from approval server
- Separate ACP server → Mitto connects to it like any other conversation
- File-based inbox → target agent reads files, no DB cross-access

**v1 needs zero changes to pykoclaw core or Mitto.** ✅

### What would benefit from a core hook (v2)

To also gate `schedule_task` with `target_conversation` crossing agent boundaries:
- Add `pre_delivery_hook` callback registration in `scheduler.py`
- Plugin registers hook → intercepts cross-boundary deliveries → routes to approval queue
- **One small hook point in core, ~10 lines**

### Read access (orthogonal to messaging)

The finance agent can **read** Tyko's workspace (via filesystem access + CLAUDE.md instruction). Tyko has **no read access** to finance workspace. This is system prompt + filesystem permissions, not a gate feature.

## Open questions

- [ ] Should the gate ACP server be a standalone process or embedded in an existing scheduler?
- [ ] Notification: should pending approvals ping the user (e.g., Matrix DM) if unattended?
- [ ] Batch mode: approve multiple messages at once, or always one-by-one?
- [ ] Expiry: should pending messages expire after N days?
- [ ] Audit log: keep full history of all approved/rejected messages?

## Deliverables

1. `pykoclaw-gate` plugin package (MCP tool + DB schema + delivery)
2. Gate ACP server (lightweight, deterministic, no LLM)
3. Systemd service definition
4. Gate policy configuration
5. Documentation: how to add gate support to an agent workspace

## Notes

- This is believed to be **novel** — no existing framework provides human-gated messaging between independent autonomous agents
- Could be extracted as a standalone open-source component later
- The ACP-based UX (Mitto buttons) is a natural fit that requires zero UI work
