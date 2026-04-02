# Canonical Memory vs Harness Logs

**Tags:** memory, architecture, plugins, harness, mnesis
**Related:** [plugin-system.md], [channel-dispatch.md]

For durable long-term memory, Pykoclaw must own the canonical normalized memory
records. Harness session files (Claude Code/OpenClaw/Pi JSONL, etc.) may be used
for bootstrap, crash recovery, backfill, or debugging, but must never be the
source of truth.

Reason: harness logs are format-coupled, provider-specific, and hostile to future
multi-harness support. A Pykoclaw-owned normalized memory layer stays valid if we
switch harnesses, support multiple backends, or eventually run more of the harness
inside Pykoclaw itself.

`mnesis` is a good implementation substrate for this memory layer, but it should
sit behind a Pykoclaw plugin/adaptor boundary (`pykoclaw-mnesis`) rather than be
imported directly into core. Core should expose minimal normalized hooks; the
plugin owns recording, summaries, and retrieval tools.

Phase 1 should be hybrid: sidecar memory + retrieval, without replacing current
harness session resume.

[plugin-system.md]: plugin-system.md
[channel-dispatch.md]: channel-dispatch.md
