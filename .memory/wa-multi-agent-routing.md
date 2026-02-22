# WhatsApp Multi-Agent Group Routing

**Tags:** whatsapp, routing, multi-agent, architecture
**Related:** [session-resume-system-prompt.md], [session-resume-retry.md]

## Key facts

- One neonize bridge process serves all agents (single process model).
- `PYKOCLAW_WA_AGENT_ROUTES` JSON file maps group JIDs → agent names.
- Each agent has its own `data_dir` → own DB, conversations, CLAUDE.md.
- The bridge DB (`wa_messages`, `wa_chats`) is shared; per-agent DBs are
  opened lazily via `_get_agent_db()`.
- Conversation names: `wa-{agent_name_lower}-{jid}`.
- Multi-agent groups get `[AgentName]:` prefixing at the send layer.
- Hard mentions route to the specific agent mentioned, not all agents.
- Agents dispatch sequentially per batch (not in parallel).
- Without the routing config env var, behavior is identical to single-agent.

## Production config

The live routing config is at `/home/agent/pipsa/agent-routes.json`.
The systemd service is `pykoclaw-whatsapp.service`.

## Gotcha: install-dev.sh runs from its own directory

`install-dev.sh` uses `cd "$(dirname "$0")"`, so it installs from whatever
workspace it lives in. When working in a feature worktree, run
`./install-dev.sh` from the **worktree root**, not the main workspace.

[session-resume-system-prompt.md]: session-resume-system-prompt.md
[session-resume-retry.md]: session-resume-retry.md
