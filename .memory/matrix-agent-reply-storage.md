# Matrix Agent Reply Storage

**Tags:** matrix, bugfix, gotcha, session-resume, context-loss
**Related:** [session-resume-retry.md], [channel-dispatch.md], [matrix-nio-gotchas.md]

## Problem

Matrix plugin never stored agent responses in `matrix_messages`. The bot's
own messages were skipped in `_handle_message` (`sender == self_user_id`),
and `_send_message` only sent to the room without storing locally.

Conversation context relied 100% on Claude session resume. When session
resume failed (SDK update, restart, corruption), the retry logic cleared
the session → new session had zero history. The XML context only contained
human messages — agent replies vanished, appearing as "missing turns."

WhatsApp didn't have this issue because Neonize re-delivers own messages
through the event loop with `is_from_me=True`.

## Fix (2026-02-22)

1. **`connection.py`**: After `_send_message`, call `store_message()` with
   `is_from_me=True` and `sender=trigger_name` so the reply persists in
   `matrix_messages` and appears in `get_new_messages_for_room()`.
2. **`dispatch.py`**: Changed `conv.session_id if conv else None` →
   `conv.session_id if conv and conv.session_id else None` to treat
   empty-string session IDs (left by failed retry cleanup) as `None`.

## Key insight

Any channel plugin whose transport doesn't echo back own messages must
explicitly store agent replies locally. Session resume is the primary
context mechanism, but local storage is the safety net.

[session-resume-retry.md]: session-resume-retry.md
[channel-dispatch.md]: channel-dispatch.md
[matrix-nio-gotchas.md]: matrix-nio-gotchas.md
