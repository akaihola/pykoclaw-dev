# Matrix Outbound Location Pins

## Status: Backlog

## Priority: 3

## TL;DR

> **Quick Summary**: Give the agent the ability to send `m.location` events to
> Matrix rooms. When the agent looks up a place, it drops a clickable map pin
> instead of just describing the address in text. Element renders these as
> static map thumbnails. Low effort — it's just a new `_send_location()` method
> and an MCP tool.
>
> **Deliverables**:
>
> - `_send_location(room_id, lat, lon, label)` method in `connection.py`
> - `send_location` MCP tool so the agent can emit pins
> - Location pin rendering in Element (automatic — Matrix spec handles it)
>
> **Estimated Effort**: Small
> **Depends On**: —

---

## Context

### Current State

The agent can only reply with text and images (Mermaid diagrams, file
references). When it describes a place, users get an address string and have
to copy-paste it into a maps app.

### Why This Matters

- Natural complement to "find me a restaurant" / "where is X?" queries
- Pairs well with scheduled tasks: "remind the group about the meetup location
  at 5pm" → agent sends text + location pin
- Trivial Matrix event — the `m.location` msgtype just needs a `geo:` URI and
  a body fallback

### Matrix `m.location` Event

```json
{
  "msgtype": "m.location",
  "body": "Restaurant Name, 123 Main St",
  "geo_uri": "geo:48.8566,2.3522",
  "info": {
    "description": "Restaurant Name"
  }
}
```

Element renders this as a static map thumbnail that opens in a map app on
click/tap.

---

## Work Objectives

### Core Objective

The agent can send map pins to Matrix rooms via an MCP tool, rendered as
clickable map previews in Element.

### Must Have

- `_send_location(room_id, lat, lon, label)` method parallel to `_send_image`
- MCP tool `send_location` with parameters: latitude, longitude, label/description
- `geo:` URI correctly formatted per RFC 5870
- Text fallback in `body` for clients that don't render maps

### Nice to Have

- Reverse geocoding in the tool (agent provides address → tool resolves coords)
- Multiple pins in one message (list of locations)

### Must NOT Have

- No inbound location handling (separate feature if needed)
- No map tile rendering server-side
- No geofencing or location tracking

---

## Verification Strategy

- Unit test: `_send_location()` calls `room_send` with correct `m.location`
  event structure
- Unit test: MCP tool returns success and triggers `_send_location`
- Manual: send location from agent → verify Element shows map thumbnail
