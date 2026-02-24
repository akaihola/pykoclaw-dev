# Matrix Typing Indicator Visible But No Response Delivered

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: The agent shows a typing indicator on Matrix but the actual
> response message never arrives in the room. This suggests the agent is
> processing the request (typing indicator is sent) but the response delivery
> fails silently — possibly due to a Matrix API error, message formatting issue,
> or an exception in the delivery pipeline that isn't surfaced.
>
> **Update 2026-02-24**: A libmagic issue was identified and fixed. This may have
> been the root cause — libmagic is used for MIME type detection in message
> handling. The fix was applied as a systemd drop-in for the pykoclaw-scheduler-tyko
> service. Monitor to confirm the issue is resolved.
>
> **Estimated Effort**: Short (investigation, possibly already fixed)
> **Depends On**: —
> **Reported**: 2026-02-24 by akaihola

---

## Context

### Problem

User observed the agent's typing indicator appear on Matrix (indicating the
agent received the message and started processing), but no response was ever
delivered to the chat room. The user said: "I saw you typing on Matrix but I
see no responses."

### Possible Causes

1. **libmagic missing/broken** (LIKELY — now fixed): `python-magic` or system
   `libmagic` not available, causing an import error or runtime exception when
   preparing the response. A `libmagic.conf` systemd drop-in was added to fix this.
2. **Matrix send_message failure**: `nio.room_send()` could fail silently if the
   access token expired, room permissions changed, or rate limiting kicked in
3. **Response too long**: Matrix has message size limits; a very long response
   might be rejected
4. **Exception in response formatting**: An error in markdown rendering or
   message chunking could prevent delivery
5. **Delivery queue issue**: If using the delivery queue, messages might get
   stuck in the queue

### Symptoms

- Typing indicator appears → agent is alive and received the message
- No response delivered → failure between "agent produces text" and "text arrives in room"
- This is different from "no typing indicator" which would indicate the message wasn't received at all

### Related

- `ACP_ISSUES_LOG.md` — for historical delivery failures
- `.memory/matrix-nio-gotchas.md` — known Matrix client pitfalls
- libmagic systemd drop-in: `/home/agent/.config/systemd/user/pykoclaw-scheduler-tyko.service.d/libmagic.conf`

---

## Investigation Plan

1. ✅ libmagic issue identified and fixed (2026-02-24)
2. Monitor Matrix responses after the fix to confirm resolution
3. If still occurring: check pykoclaw-matrix logs for send errors
4. Check Matrix room state (permissions, power levels)
5. Review delivery queue for stuck messages

---

## TODOs

- [x] 1. Identify libmagic as potential root cause
- [x] 2. Apply libmagic fix (systemd drop-in)
- [ ] 3. Monitor to confirm the fix resolves the issue
- [ ] 4. If not resolved: deeper investigation into Matrix delivery pipeline
- [ ] 5. Add error logging/alerting for failed message deliveries
