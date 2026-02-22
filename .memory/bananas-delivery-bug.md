# BANANAS Delivery Bug — Bare target_conversation

**Tags:** scheduler, delivery, whatsapp, routing, bug-fix
**Related:** [session-resume-system-prompt.md], [plugin-config-env-file.md]

## Problem

When the agent sets `target_conversation` to a bare identifier (e.g.
`120363...@g.us` for WhatsApp, `!room:matrix.org` for Matrix),
`parse_channel_prefix()` falls back to `"chat"` since there's no `-` in
the string. Deliveries get enqueued with `channel_prefix="chat"` and no
channel plugin ever picks them up — they sit **pending forever**.

The task status shows `completed` (agent ran successfully) but messages
never arrive.

## Root cause

`parse_channel_prefix()` splits on `-` and defaults to `"chat"`. Bare
identifiers have no `-` prefix. The scheduler naively trusted the target
conversation to be well-formed.

## Fix

Added `resolve_delivery_target()` in `scheduler.py`:

1. If the target has a known prefix (`wa-`, `matrix-`, etc.) → use as-is.
   Known prefixes come from `KNOWN_CHANNEL_PREFIXES` in `db.py`.
2. If bare → inherit prefix from `task.conversation`.
3. If the bare target matches the origin suffix exactly or on a `-`
   boundary → reuse the full origin name (preserves agent routing
   segments like `wa-tyko-...`).
4. Otherwise → prepend the origin prefix.

## Diagnosis checklist

If reminders/scheduled tasks "complete" but don't arrive:

1. Check `delivery_queue` for `status='pending'` entries.
2. Check `channel_prefix` — `"chat"` is almost always wrong.
3. Check `conversation` — bare JIDs without prefixes won't route.

[session-resume-system-prompt.md]: session-resume-system-prompt.md
[plugin-config-env-file.md]: plugin-config-env-file.md
