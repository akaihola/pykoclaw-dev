# Slack Sender Name Resolution

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: The Slack gateway passes raw user IDs (e.g. `U07UGSQQCUS`)
> to the agent in the XML message context. The agent cannot identify who is
> speaking — it cannot distinguish Jussi, Antti, or Tyko from opaque identifiers.
> Fix by resolving each user ID to a display name (with the user ID as fallback)
> via the Slack `users.info` API, caching results, and storing the resolved name
> in the database alongside (or replacing) the raw ID.
>
> **Deliverables**:
>
> - `UserNameCache` helper in `handler.py` — async, LRU-style, backed by `users.info`
> - `slack_users` table in DB for persistent cross-restart name caching
> - `store_message()` receives resolved `sender_name` in addition to `sender_id`
> - `format_xml_message()` emits both `sender` (display name) and `sender_id` attributes
> - System prompt updated to explain sender attribute semantics
> - Tests for cache lookup, fallback, and XML formatting
>
> **Estimated Effort**: Short
> **Depends On**: Nothing (standalone change to pykoclaw-slack)
> **Parallel Execution**: YES — DB schema + cache helper can be done in parallel

---

## Context

### The Problem

When a message arrives, `_handle_message()` in `connection.py` extracts:

```python
user: str = event.get("user", "")
```

This is the Slack member ID — always an opaque string like `U07UGSQQCUS`.
It is stored as-is in `slack_messages.sender` and passed directly to
`format_xml_message()`, which produces:

```xml
<message sender="U07UGSQQCUS" time="2026-03-04T09:12:00+00:00">
  Hei Agentti, voisitko ...
</message>
```

The agent has no way to know that `U07UGSQQCUS` is Jussi. As one agent put it:

> "Näen viestit lähettäjätunnuksina (esim. U07UGSQQCUS, U08BWCL1XH9), mutta
> en näe nimiä suoraan. En siis tiedä kuka on Jussi, kuka Antti ja kuka Tyko,
> ellei joku kerro minulle."

### The Fix

Use the Slack API `users.info` to resolve each user ID to a display name on
first encounter, cache it (in memory + DB), and include the name in the XML
context passed to the agent:

```xml
<message sender="Jussi" sender_id="U07UGSQQCUS" time="2026-03-04T09:12:00+00:00">
  Hei Agentti, voisitko ...
</message>
```

### Design Decisions

- **Keep `sender_id`** alongside `sender` in the XML — so the agent can
  disambiguate when two people share a display name and can correlate names
  to IDs in tool calls if needed.
- **Persist the cache** in a `slack_users` table — prevents a burst of
  `users.info` calls on every restart and keeps names available without
  a live API call.
- **Cache TTL: 24 h** — display names change rarely; stale names for a day
  are acceptable. On TTL expiry, refetch in background; serve stale in the
  meantime.
- **Fallback chain**: `display_name` → `real_name` → `name` (username) → raw ID.
  Never fail silently.
- **Bots**: for bot messages (`event.get("bot_id")`), use the `bot_profile.name`
  field directly; no `users.info` call needed.

---

## Work Objectives

### Core Objective

The agent receives human-readable names in the `sender` XML attribute for every
message, with no observable latency increase (name resolution is async and
cached).

### Definition of Done

- [ ] `<message sender="Jussi" sender_id="U07UGSQQCUS" ...>` in agent prompt
- [ ] Name resolved on first message from each user, cached in memory + DB
- [ ] Cache survives service restart (DB-backed)
- [ ] TTL of 24 h with background refresh (stale-while-revalidate)
- [ ] Bot messages use `bot_profile.name` or `username`, not raw bot ID
- [ ] System prompt mentions that `sender` is a display name and `sender_id`
      is the Slack member ID
- [ ] Unit tests for cache, fallback chain, and XML format

### Must NOT Have

- Blocking `users.info` calls on the hot path (must be async / pre-warmed)
- Hardcoded user ID → name mappings
- Name stored only in memory (must survive restart)

---

## Tasks

### 1. Add `slack_users` table

**File**: `pykoclaw-slack/src/pykoclaw_slack/handler.py` (or `db.py` if extracted)

Add migration in the plugin's `get_db_migrations()` (in `__init__.py` or
wherever the plugin class lives):

```sql
CREATE TABLE IF NOT EXISTS slack_users (
    user_id   TEXT PRIMARY KEY,
    name      TEXT NOT NULL,
    fetched_at TEXT NOT NULL   -- ISO 8601 UTC
);
```

Also add `ALTER TABLE ADD COLUMN` guard for the new columns on existing installs
(see CLAUDE.md gotcha: `IF NOT EXISTS` never alters existing tables).

### 2. `UserNameCache` helper in `handler.py`

```python
import time
from dataclasses import dataclass

CACHE_TTL_SECONDS = 86_400  # 24 h

@dataclass
class _CacheEntry:
    name: str
    fetched_at: float  # monotonic

class UserNameCache:
    """Async LRU-style cache for Slack user ID → display name resolution.

    Layer 1: in-process dict (fastest, lost on restart)
    Layer 2: slack_users DB table (survives restart)
    Layer 3: users.info Slack API call (authoritative, rate-limited)
    """

    def __init__(self, db: DbConnection, slack_client: AsyncWebClient) -> None:
        self._db = db
        self._client = slack_client
        self._cache: dict[str, _CacheEntry] = {}

    async def resolve(self, user_id: str) -> str:
        """Return display name for user_id, fetching if necessary."""
        entry = self._cache.get(user_id)
        if entry and (time.monotonic() - entry.fetched_at) < CACHE_TTL_SECONDS:
            return entry.name

        # Try DB
        row = self._db.fetchone(
            "SELECT name, fetched_at FROM slack_users WHERE user_id = ?", (user_id,)
        )
        if row:
            # Warm in-process cache
            self._cache[user_id] = _CacheEntry(name=row["name"],
                                               fetched_at=time.monotonic())
            # If DB entry is fresh enough, use it
            age = (datetime.now(timezone.utc) -
                   datetime.fromisoformat(row["fetched_at"])).total_seconds()
            if age < CACHE_TTL_SECONDS:
                return row["name"]

        # Fetch from Slack API
        name = await self._fetch_from_slack(user_id)
        self._store(user_id, name)
        return name

    async def _fetch_from_slack(self, user_id: str) -> str:
        try:
            resp = await self._client.users_info(user=user_id)
            profile = resp["user"].get("profile", {})
            return (
                profile.get("display_name")
                or profile.get("real_name")
                or resp["user"].get("name")
                or user_id
            )
        except Exception:
            log.warning("users.info failed for %s — using raw ID", user_id)
            return user_id

    def resolve_bot(self, event: dict) -> str:
        """Return name for a bot message event (no API call needed)."""
        bot_profile = event.get("bot_profile") or {}
        return bot_profile.get("name") or event.get("username") or event.get("bot_id", "bot")

    def _store(self, user_id: str, name: str) -> None:
        now = datetime.now(timezone.utc).isoformat()
        self._db.execute(
            "INSERT OR REPLACE INTO slack_users (user_id, name, fetched_at) VALUES (?, ?, ?)",
            (user_id, name, now),
        )
        self._db.commit()
        self._cache[user_id] = _CacheEntry(name=name, fetched_at=time.monotonic())
```

### 3. Thread `UserNameCache` through `SlackConnection`

**File**: `pykoclaw-slack/src/pykoclaw_slack/connection.py`

- Instantiate `UserNameCache` in `run_async()` after `self._app` is created.
- Pass `self._app.client` as `slack_client`.
- In `_handle_message()`, after extracting `user`:

```python
is_bot = bool(event.get("bot_id")) or event.get("subtype") == "bot_message"
if is_bot:
    sender_name = self._name_cache.resolve_bot(event)
else:
    sender_name = await self._name_cache.resolve(user)

store_message(
    self._db,
    channel_id=channel_id,
    sender_id=user,
    sender_name=sender_name,
    ...
)
```

### 4. Update `store_message()` and `slack_messages` schema

**File**: `pykoclaw-slack/src/pykoclaw_slack/handler.py`

Add `sender_name TEXT` column to `slack_messages` (with `ALTER TABLE` guard).
Update `store_message()` signature:

```python
def store_message(
    db: DbConnection,
    channel_id: str,
    sender_id: str,       # renamed from sender
    sender_name: str,     # new
    text: str,
    timestamp: str,
    slack_ts: str,
    thread_ts: str | None,
    is_from_me: bool,
) -> None:
```

Update the INSERT to include both columns.

### 5. Update `get_new_messages_for_channel()` and `format_xml_message()`

**File**: `pykoclaw-slack/src/pykoclaw_slack/handler.py`

- `get_new_messages_for_channel()` returns `(sender_id, sender_name, timestamp, text)` tuples.
- `format_xml_message()`:

```python
def format_xml_message(
    sender_name: str, sender_id: str, timestamp: str, content: str
) -> str:
    return (
        f'<message sender="{html_escape(sender_name)}"'
        f' sender_id="{html_escape(sender_id)}"'
        f' time="{html_escape(timestamp)}">'
        f"{html_escape(content)}</message>"
    )
```

- `format_xml_messages()` updated accordingly.

### 6. Update system prompt

**File**: `pykoclaw-slack/src/pykoclaw_slack/connection.py`, `_build_system_prompt()`

Add a sentence clarifying the XML attributes:

```
Each message in the context has a `sender` attribute (the person's display name)
and a `sender_id` attribute (their Slack member ID, e.g. U07UGSQQCUS).
Use `sender` to address or refer to people by name.
```

### 7. Tests

**Context — current coverage gap:**
`_handle_agent_trigger()` (the function changed by this feature) has 0% test
coverage. The existing `test_connection_features.py` mocks out `BatchAccumulator`
and stops at the accumulator boundary. This means the dispatch → extract reply
→ send → store → cursor pipeline has no safety net. The tests below add that
net before touching the code.

**File**: `pykoclaw-slack/tests/test_sender_resolution.py` (new)

```
test_resolve_cached_in_memory         — second call returns cached name, no API call
test_resolve_from_db_on_restart       — warm in-process cache from DB row on startup
test_resolve_calls_users_info         — fresh user ID triggers API call, stores result
test_resolve_fallback_chain           — display_name → real_name → name → raw ID
test_resolve_api_failure_returns_id   — graceful fallback on API error
test_resolve_bot_uses_bot_profile     — bot message uses bot_profile.name, no API call
test_resolve_db_stale_refetches       — DB entry older than TTL triggers re-fetch
test_format_xml_includes_sender_id    — XML has both sender and sender_id attrs
```

**File**: `pykoclaw-slack/tests/test_handler.py` (extend)

- Update `store_message` call sites to pass `sender_id` + `sender_name`.
- Update `format_xml_message` / `format_xml_messages` assertions to expect
  both `sender` (name) and `sender_id` attributes.
- Update `get_new_messages_for_channel` return-value checks to include
  `sender_id` and `sender_name` columns.

**File**: `pykoclaw-slack/tests/test_connection_dispatch.py` (new)

This file covers `_handle_agent_trigger()` end-to-end with a mocked
`dispatch_to_agent`. Without this, a regression in the dispatch path
(wrong XML format, wrong cursor update, failure to send reply) would go
undetected.

```
test_trigger_dispatches_with_resolved_names
    — XML context passed to dispatch contains sender="Jussi" sender_id="U07…"
    — mock UserNameCache returns "Jussi"; verify format_xml_messages output

test_trigger_sends_reply_to_channel
    — dispatch returns full_text with <reply>hello</reply>
    — _send_message called with extracted "hello", correct channel + thread_ts

test_trigger_stores_sent_message
    — after sending, store_message called with is_from_me=True

test_trigger_updates_cursor
    — update_agent_cursor called with last message timestamp

test_trigger_silence_when_no_reply_tags
    — dispatch returns full_text with no <reply> tags
    — _send_message NOT called; cursor still updated

test_trigger_hard_mention_empty_retries_fresh
    — dispatch returns empty text in < 3s on first call; second call returns reply
    — verifies fresh-session retry logic (upsert_conversation + re-dispatch)

test_trigger_no_messages_returns_early
    — get_new_messages_for_channel returns []
    — dispatch NOT called
```

---

## Deployment

No config changes required — feature is on by default and requires no new env vars.

After deploying:

```bash
./install-dev.sh
```

The `slack_users` table and new `sender_name` column are created automatically
via the plugin migration logic on first startup.

---

## Risks

| Risk                                          | Mitigation                                                                                                                           |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `users.info` rate limit (Tier 4: 100 req/min) | Cache with 24 h TTL; small workspaces will hit at most a dozen users total                                                           |
| Bot events missing `bot_profile`              | Fallback chain: `bot_profile.name` → `username` → `bot_id` → `"bot"`                                                                 |
| Existing DB rows have no `sender_name`        | `ALTER TABLE ADD COLUMN sender_name TEXT DEFAULT ''`; old rows show empty name, agent sees raw ID as before — acceptable for history |
| `users.info` returns deactivated user         | Still returns a name; acceptable                                                                                                     |

---

## Verification

```bash
# Unit tests
cd ~/pykoclaw-dev/slack-sender-names
uv run pytest pykoclaw-slack/tests/ -v -k "sender"

# Manual: trigger a message and check the debug log for the XML context
PYKOCLAW_LOG_LEVEL=DEBUG uv run pykoclaw slack run 2>&1 | rg "sender="
```
