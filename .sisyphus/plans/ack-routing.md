# Automated Acknowledgement Routing

## Status: Backlog
## Priority: 3

## TL;DR

> **Quick Summary**: When an agent sends a message to an external channel
> (WhatsApp, Matrix room, Telegram) on behalf of the user, route the
> acknowledgement ("Message sent to X") to a configured private Matrix DM
> instead of polluting the target channel or silently dropping it.
> Uses the existing `<reply>` tag convention: text inside `<reply>` tags
> goes to the target channel, everything outside goes to the ack room.
>
> **Deliverables**:
> - `split_reply_and_ack()` function in pykoclaw core (replaces `strip_reply_tags()`)
> - `PYKOCLAW_ACK_ROOM` env var in core `Settings`
> - Updated `run_task()` in scheduler to split-and-route
> - Updated `_handle_agent_trigger()` in Matrix bridge to route non-reply text
> - Updated `_dispatch_for_agent()` in WhatsApp bridge to route non-reply text
> - Consolidation: remove duplicate `_extract_reply()` from both bridges
> - Tests for the split function and ack routing delivery
>
> **Estimated Effort**: Short
> **Depends On**: `feature/cross-agent-delivery` branch (for cross-workspace acks)
> **Parallel Execution**: NO — core first, then bridges, then tests

---

## Context

### Original Problem

Agents have three messaging paths, each with an ack problem:

1. **Scheduled tasks** — Scheduler delivers `strip_reply_tags(result_text)` to
   `target_conversation`. Non-reply text (acks, reasoning) is silently dropped.
2. **Live bridge conversations** — Bridges extract `<reply>` content and send
   it to the originating room. Non-reply text is silently dropped.
3. **Tool-based sends** — Agent calls `send_message` / `send_matrix_message`
   to send to a target. The `<reply>` ack goes back to the originating room
   (polluting group chats with meta-commentary like "Message sent!").

In all three cases, the user never gets a private confirmation of what happened.

### Prior Art: Ressu/Anu Rautanen Incident (2026-02-24)

**The leak:** Ressu's first attempt used `target_conversation: "wa-<jid>"`,
routing the agent's full text output (including internal monologue) directly
to Anu Rautanen's WhatsApp.

**The manual fix:** Restructured each `schedule_task` call:
```json
{
  "prompt": "Send WhatsApp message...\nRespond only: \"Viesti lähetetty Anulle.\"",
  "target_conversation": "matrix-!RHetEGOWFgXEsOojtZ:matrix.org",
  "context_mode": "isolated"
}
```
- Actual message: sent via `send_message` tool inside the task
- `target_conversation`: points to private Matrix DM for ack delivery
- Prompt: constrains output to a short confirmation only

This worked but requires manual prompt engineering per task and doesn't cover
live bridge conversations at all.

**Evidence:** Session `ae1e115b` in pipsa workspace. Five Matrix ack messages
delivered to `!RHetEGOWFgXEsOojtZ:matrix.org` between 17:55-18:15 UTC:
"Testiviesti lähetetty", "Testiviesti #2 lähetetty", "Testiviesti #3 lähetetty",
"Viesti lähetetty Anulle", "Esittely lähetetty Anulle".

### Existing Infrastructure

The building blocks are all in place:

| Component | Location | What it does |
|-----------|----------|-------------|
| `strip_reply_tags()` | `pykoclaw/scheduler.py` | Extracts `<reply>` content, drops rest |
| `_extract_reply()` | `pykoclaw-matrix/connection.py`, `pykoclaw-whatsapp/connection.py` | Same logic, duplicated |
| `resolve_delivery_target()` | `pykoclaw/scheduler.py` | Resolves `target_conversation` + prefix |
| `enqueue_delivery()` | `pykoclaw/db.py` | Queues messages for bridge delivery |
| `extra_db_paths` | `pykoclaw-matrix/config.py` | Cross-agent delivery (unmerged: `feature/cross-agent-delivery`) |
| Delivery pollers | Both bridges' `_delivery_poll_loop()` | Pick up queued messages by `channel_prefix` |

### Design Decision

**Split-and-route at the delivery layer**, not in the agent or system prompt.

The `<reply>` tag convention already separates "content for the channel" from
"everything else." The only missing piece: "everything else" is currently
dropped. Instead, route it to a configured ack room.

Why this approach:
- No new MCP tools for the agent to learn or misuse
- No system prompt changes needed
- Works across all bridges automatically
- Agents don't need to change behavior — they already use `<reply>` tags
- Follows pykoclaw's "intentionally minimal core" philosophy

---

## Work Objectives

### Core Objective

Non-reply text from agent output gets automatically routed to a configured
Matrix room (the user's private DM) instead of being silently dropped.

### Definition of Done

- [ ] Agent sends WhatsApp message → ack appears in Matrix DM, not in target chat
- [ ] Scheduled task with `<reply>` tags → reply to target, ack to Matrix DM
- [ ] Live Matrix bridge conversation → reply to room, ack to DM (if different room)
- [ ] Live WhatsApp bridge conversation → reply to chat, ack to DM
- [ ] No ack delivered when `PYKOCLAW_ACK_ROOM` is unset (backward compatible)
- [ ] Duplicate `_extract_reply()` removed from both bridges

### Must NOT Have

- New MCP tools (no `send_ack` tool — this is transparent to agents)
- Changes to agent system prompts
- Hard-coded room IDs in public code
- Retry/backoff logic for ack delivery (keep simple)

---

## Tasks

### 1. Add `ack_room` to core Settings + `split_reply_and_ack()`

**Files**: `pykoclaw/src/pykoclaw/config.py`, `pykoclaw/src/pykoclaw/scheduler.py`

Add to `Settings`:
```python
ack_room: str | None = None  # env: PYKOCLAW_ACK_ROOM
```

Add alongside `strip_reply_tags()`:
```python
def split_reply_and_ack(text: str) -> tuple[str | None, str | None]:
    """Split agent output into reply content and ack/non-reply content.

    Returns (reply_text, ack_text) where either may be None.
    If no <reply> tags found, entire text is the reply (backward compat).
    """
    matches = _REPLY_TAG_RE.findall(text)
    if not matches:
        return text, None  # No tags → everything is reply

    reply_parts = [m.strip() for m in matches if m.strip()]
    reply_text = "\n".join(reply_parts) if reply_parts else None

    remainder = _REPLY_TAG_RE.sub("", text).strip()
    ack_text = remainder if remainder else None

    return reply_text, ack_text
```

Keep `strip_reply_tags()` as a thin wrapper for backward compatibility.

### 2. Update scheduler `run_task()` to split-and-route

**File**: `pykoclaw/src/pykoclaw/scheduler.py`

Replace:
```python
message=strip_reply_tags(result_text),
```

With:
```python
reply_text, ack_text = split_reply_and_ack(result_text)

if reply_text:
    delivery_conversation, channel_prefix = resolve_delivery_target(task)
    enqueue_delivery(db, ..., conversation=delivery_conversation,
                     channel_prefix=channel_prefix, message=reply_text)

if ack_text and settings.ack_room:
    enqueue_delivery(db, ..., conversation=f"matrix-{settings.ack_room}",
                     channel_prefix="matrix", message=ack_text)
```

### 3. Update Matrix bridge `_handle_agent_trigger()`

**File**: `pykoclaw-matrix/src/pykoclaw_matrix/connection.py`

Replace `_extract_reply()` usage with `split_reply_and_ack()`:
```python
from pykoclaw.scheduler import split_reply_and_ack
from pykoclaw.config import settings as core_settings

reply_text, ack_text = split_reply_and_ack(result.full_text)
if reply_text:
    await self._send_message(room_id, reply_text)
    # ... store message ...

# Route ack to DM (skip if already in the ack room)
if ack_text and core_settings.ack_room and core_settings.ack_room != room_id:
    enqueue_delivery(self._db, task_id="bridge-ack", task_run_log_id=None,
                     conversation=f"matrix-{core_settings.ack_room}",
                     channel_prefix="matrix", message=ack_text)
```

Remove the local `_extract_reply()` function.

### 4. Update WhatsApp bridge `_dispatch_for_agent()`

**File**: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`

Same pattern as Matrix:
```python
from pykoclaw.scheduler import split_reply_and_ack
from pykoclaw.config import settings as core_settings

reply_text, ack_text = split_reply_and_ack(result.full_text)
if reply_text:
    formatted = markdown_to_whatsapp(reply_text)
    # ... send to WhatsApp ...

if ack_text and core_settings.ack_room:
    enqueue_delivery(agent_db, task_id="bridge-ack", task_run_log_id=None,
                     conversation=f"matrix-{core_settings.ack_room}",
                     channel_prefix="matrix", message=ack_text)
```

Remove the local `_extract_reply()` function.

### 5. Tests

**File**: `pykoclaw/tests/test_delivery.py` (extend existing)

```
test_split_reply_and_ack_with_tags       — reply + ack separated
test_split_reply_and_ack_no_tags         — backward compat (entire text = reply)
test_split_reply_and_ack_only_reply      — no remainder → ack is None
test_split_reply_and_ack_multiple        — multiple <reply> blocks
test_scheduler_enqueues_ack_to_ack_room  — two deliveries: target + ack room
test_scheduler_no_ack_when_unconfigured  — ack_room=None → no ack delivery
```

---

## Dependencies

| Dependency | Status | Impact |
|-----------|--------|--------|
| `feature/cross-agent-delivery` (pykoclaw-matrix + pykoclaw-whatsapp) | Unmerged | Required for cross-workspace acks (e.g. Ressu's ack → Tyko's Matrix). Same-workspace acks work without it. |

**Merge `feature/cross-agent-delivery` first.** It adds `extra_db_paths` to
the Matrix bridge and fixes `send_message` delivery in WhatsApp — both are
prerequisites for ack delivery from non-Matrix workspaces.

---

## Deployment

1. Set `PYKOCLAW_ACK_ROOM=!RHetEGOWFgXEsOojtZ:matrix.org` in workspace `.env`
   files (or a shared env config)
2. Restart: `pykoclaw-scheduler-*`, `pykoclaw-matrix-tyko`, `pykoclaw-whatsapp`

### Phased Rollout

1. **Phase 1**: Scheduler path only (covers scheduled task acks)
2. **Phase 2**: Matrix bridge (after validating Phase 1)
3. **Phase 3**: WhatsApp bridge (after validating Phase 2)

---

## Risks

| Risk | Mitigation |
|------|-----------|
| **Noisy ack room** — agents produce lots of non-reply text | System prompts already tell agents text outside `<reply>` tags is not delivered. Most non-reply output is tool reasoning that doesn't appear as text. Monitor and filter if needed. |
| **Backward compatibility** — `split_reply_and_ack()` must match `strip_reply_tags()` behavior when no tags present | Explicit: no tags → `(full_text, None)`. Same as current behavior. Tested. |
| **Cross-workspace contention** — ack writes from Ressu's DB need Matrix bridge to poll extra DBs | Depends on `feature/cross-agent-delivery`. Without it, same-workspace acks still work. |

---

## Verification Strategy

### Unit tests (pytest)
```bash
uv run pytest pykoclaw/tests/test_delivery.py -v -k "split_reply_and_ack or ack_room"
```

### Manual QA
1. Schedule a task that uses `<reply>` tags → verify reply goes to target, ack to DM
2. Send a WhatsApp message via agent → verify ack appears in Matrix DM
3. With `PYKOCLAW_ACK_ROOM` unset → verify no ack delivery (backward compat)
