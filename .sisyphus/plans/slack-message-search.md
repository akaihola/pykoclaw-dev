# Slack Message Search

## Status: Backlog

## Priority: 2

## TL;DR

> **Quick Summary**: Give the Slack agent the ability to search messages —
> both in channels it has been actively watching and in any channel it is
> joined in (including historical messages before the bot started running).
>
> Two orthogonal additions:
>
> 1. **DB one-liner knowledge** — extend `_build_system_prompt()` with the
>    SQLite DB path, the `slack_messages` schema, and a copy-pasteable
>    read-only one-liner example. The agent already has the `Bash` tool and
>    `permission_mode="bypassPermissions"`, so it can execute arbitrary SQL
>    queries immediately with no new MCP tool required.
> 2. **`fetch_channel_history` MCP tool** — calls `conversations.history`
>    to pull messages from any channel the bot is joined in (including
>    history predating the bot's first start), stores them in
>    `slack_messages` via an upsert, and returns the batch as an XML block.
>    After fetching, the agent can search with any SQL it writes.
>
> **Deliverables**:
>
> - Extended `_build_system_prompt()` in `connection.py` (~8 lines)
> - `store_messages_from_api()` upsert helper in `handler.py`
> - Unique index migration on `(channel_id, slack_ts)` in `__init__.py`
> - `fetch_channel_history` MCP tool in `__init__.py`
> - Tests: unique-index migration, upsert idempotence, tool round-trip
>
> **Estimated Effort**: Short
> **Parallel Execution**: NO — migration first, then helper, then tool, then
> prompt, then tests

---

## Context

### The capability gap

The Slack plugin stores every inbound message in `slack_messages`, but the
agent currently has no way to query that store other than the
`get_slack_history` MCP tool — which only returns messages _newer than the
agent cursor_ (i.e. the "unread" window). There is no way to search by
keyword, sender, date range, or cross-channel, and there is no way to
retrieve history from a channel that the bot has joined but never had a
triggered dispatch in.

### Why no dedicated `search_slack_messages` MCP tool

A bespoke tool would only expose a fixed API surface (e.g. a `query` string
and optional `channel_id`). SQL is already a complete query language.
The agent runs inside a Claude Code harness with the `Bash` tool enabled and
`permission_mode="bypassPermissions"` — it can execute a `python3 -c "..."`
one-liner without any additional scaffolding. Pointing it at the SQLite DB
with a one-liner example in the system prompt gives it:

- Full-text search (`LIKE`, `GLOB`, FTS5 if ever added)
- Filter by `sender`, `channel_id`, `thread_ts`, date range, `is_from_me`
- `GROUP BY`, `ORDER BY`, `LIMIT`, `OFFSET`
- Joins to `slack_channels` for channel names
- Any combination of the above

No MCP tool can match that flexibility. The only thing to "implement" is
telling the agent the DB path, the schema, and that `?mode=ro` URI opens it
read-only.

### Why `fetch_channel_history` is still needed

The local `slack_messages` table only contains messages the listener has
actually received. It has two gaps:

1. Messages from channels the bot joined but has never been mentioned in
   (the `on_message` event fires, but the cursor never moves so nothing is
   stored until a batch flush runs — and some channels may have no hard
   mentions for days).
2. All history from _before_ the bot was running (or before the bot was
   invited to a channel).

The Slack `conversations.history` API fills both gaps. It returns up to
1 000 messages per page and is available to bot tokens with
`channels:history` / `groups:history` scope. The tool fetches, upserts, and
returns the batch, after which the agent can query the DB directly.

### Prior design discussion

Initial design included a dedicated `search_slack_messages` MCP tool. This
was dropped in favour of the system-prompt one-liner approach: same
capability, zero ongoing maintenance cost, maximum flexibility.

---

## Architecture

```
_build_system_prompt()   ← tells agent: DB path, schema, one-liner example
           │
           ▼
       Agent (Bash tool)
           │ python3 -c "import sqlite3; ..."
           ▼
    pykoclaw.db (WAL mode, read-only URI)
           │
    slack_messages table   ◄─────────────── fetch_channel_history MCP tool
                                            (calls conversations.history API,
                                             upserts via store_messages_from_api)
```

WAL journal mode (already set: `db.execute("PRAGMA journal_mode=WAL")`) means
the agent's read-only one-liner and the live server writer can coexist without
blocking each other.

---

## Work Objectives

### Core Objective

The Slack agent can search any message in any joined channel by composing
arbitrary SQL queries, and can pull in historical messages from channels not
yet cached locally.

### Definition of Done

- [ ] Agent can search cached messages with a raw SQL one-liner (Bash tool)
- [ ] Agent knows the DB path and schema without having to ask
- [ ] Agent can call `fetch_channel_history` to sync a channel's full history
- [ ] Fetching the same messages twice does not create duplicate rows
- [ ] `fetch_channel_history` fails gracefully when the bot is not in the channel
- [ ] All existing tests pass; new tests cover the three above behaviours

### Must NOT Have

- A `search_slack_messages` MCP tool (see design rationale above)
- Any change to `get_slack_history` or the agent cursor logic
- Writes to the DB from the agent's one-liner (enforced by `?mode=ro` URI in
  the example; documented but not technically enforced)
- New Slack OAuth scopes beyond `channels:history` / `groups:history` (which
  a typical Slack bot already requests)

---

## Tasks

### 1. Unique index migration on `(channel_id, slack_ts)`

**File**: `pykoclaw-slack/src/pykoclaw_slack/__init__.py`
**Method**: `get_db_migrations()`

Add a new migration entry (after the `attachment_path` `ALTER TABLE`):

```python
dedent("""\
    CREATE UNIQUE INDEX IF NOT EXISTS uq_slack_messages_channel_ts
        ON slack_messages (channel_id, slack_ts)"""),
```

This makes `INSERT OR IGNORE` safe for the new upsert helper and also
makes historical re-fetches fully idempotent. No data loss — `IF NOT EXISTS`
silently no-ops on an already-migrated DB.

**Test**: `test_migration_unique_index` — create a DB, run `init_db()`, insert
two rows with identical `(channel_id, slack_ts)` using `INSERT OR IGNORE`,
assert only one row is present.

---

### 2. `store_messages_from_api()` upsert helper

**File**: `pykoclaw-slack/src/pykoclaw_slack/handler.py`

Add after `store_message()`:

```python
def store_messages_from_api(
    db: DbConnection,
    channel_id: str,
    messages: list[dict[str, Any]],
) -> int:
    """Upsert a batch of raw Slack API message dicts into slack_messages.

    Uses INSERT OR IGNORE on the (channel_id, slack_ts) unique index so
    calling this multiple times with overlapping data is idempotent.

    Args:
        db:         Open DB connection.
        channel_id: Slack channel ID the messages belong to.
        messages:   Raw message dicts from conversations.history
                    (each has 'ts', 'user', 'text' keys at minimum).

    Returns:
        Number of rows actually inserted (0 on full overlap).
    """
    inserted = 0
    for msg in messages:
        slack_ts = msg.get("ts", "")
        if not slack_ts:
            continue
        iso_ts = datetime.fromtimestamp(
            float(slack_ts), tz=timezone.utc
        ).isoformat()
        cursor = db.execute(
            dedent("""\
                INSERT OR IGNORE INTO slack_messages
                    (channel_id, sender, text, timestamp, slack_ts,
                     thread_ts, is_from_me, attachment_path)
                VALUES (?, ?, ?, ?, ?, ?, 0, NULL)"""),
            (
                channel_id,
                msg.get("user", ""),
                msg.get("text", ""),
                iso_ts,
                slack_ts,
                msg.get("thread_ts"),
            ),
        )
        inserted += cursor.rowcount
    db.commit()
    return inserted
```

Also add `from datetime import datetime, timezone` if not already imported
at the top of `handler.py` (it currently imports neither — both are needed).

**Test**: `test_store_messages_from_api_idempotent` — call the function twice
with the same message list and assert the row count is 1 after both calls.

---

### 3. `fetch_channel_history` MCP tool

**File**: `pykoclaw-slack/src/pykoclaw_slack/__init__.py`
**Method**: `get_mcp_servers()`

Add alongside `send_slack_message` and `get_slack_history`:

```python
from slack_sdk.web.async_client import AsyncWebClient as _AsyncWebClient

_slack_client = _AsyncWebClient(token=self._config_instance.bot_token)
# (or: call get_config() inline — see note below)

@tool(
    "fetch_channel_history",
    dedent("""\
        Fetch recent message history from a Slack channel via the Slack API
        and store it in the local database. Use this to access messages from
        channels not yet cached, or historical messages predating the bot's
        first run.

        The bot must be a member of the channel. After fetching, use the
        Bash tool with a sqlite3 one-liner to search or filter the results.

        Returns an XML block of the fetched messages and a count of new rows
        inserted (0 = all messages were already cached)."""),
    {
        "type": "object",
        "properties": {
            "channel_id": {
                "type": "string",
                "description": "Slack channel ID (e.g. C01234567).",
            },
            "limit": {
                "type": "integer",
                "description": (
                    "Maximum number of messages to fetch (1–200, default 100). "
                    "Slack returns them newest-first; the tool reverses to "
                    "chronological order before returning."
                ),
            },
            "oldest": {
                "type": "string",
                "description": (
                    "Fetch messages after this Unix timestamp (exclusive). "
                    "Useful for incremental syncs. Optional."
                ),
            },
            "latest": {
                "type": "string",
                "description": (
                    "Fetch messages before this Unix timestamp (inclusive). "
                    "Optional."
                ),
            },
        },
        "required": ["channel_id"],
    },
)
async def fetch_channel_history(args: dict[str, Any]) -> dict[str, Any]:
    channel_id = args["channel_id"]
    limit = min(int(args.get("limit", 100)), 200)
    kwargs: dict[str, Any] = {
        "channel": channel_id,
        "limit": limit,
    }
    if args.get("oldest"):
        kwargs["oldest"] = args["oldest"]
    if args.get("latest"):
        kwargs["latest"] = args["latest"]

    try:
        resp = await _slack_client.conversations_history(**kwargs)
    except Exception as exc:
        return {
            "content": [
                {
                    "type": "text",
                    "text": f"Error fetching history for {channel_id}: {exc}",
                }
            ]
        }

    if not resp.get("ok"):
        error = resp.get("error", "unknown_error")
        return {
            "content": [
                {
                    "type": "text",
                    "text": (
                        f"Slack API error for {channel_id}: {error}. "
                        "Is the bot a member of this channel?"
                    ),
                }
            ]
        }

    raw_messages: list[dict[str, Any]] = resp.get("messages", [])
    # API returns newest-first; reverse to chronological order.
    raw_messages = list(reversed(raw_messages))

    inserted = store_messages_from_api(db, channel_id, raw_messages)

    if not raw_messages:
        return {
            "content": [
                {"type": "text", "text": f"No messages found in {channel_id}."}
            ]
        }

    # Build XML for immediate agent consumption.
    tuples = [
        (
            m.get("user", ""),
            datetime.fromtimestamp(
                float(m["ts"]), tz=timezone.utc
            ).isoformat(),
            m.get("text", ""),
            None,
        )
        for m in raw_messages
        if m.get("ts")
    ]
    xml = format_xml_messages(tuples)

    summary = (
        f"Fetched {len(raw_messages)} messages from {channel_id}. "
        f"{inserted} new rows inserted into local DB.\n\n{xml}"
    )
    return {"content": [{"type": "text", "text": summary}]}
```

**Implementation note — Slack client instantiation**: `get_mcp_servers()` is
called with `(db, conversation)` and has no reference to a live
`AsyncWebClient`. The cleanest approach is to call `get_config()` inside the
method (it's cached after first call) and create a module-level `_slack_client`
lazily:

```python
# At top of get_mcp_servers():
cfg = get_config()
slack_client = AsyncWebClient(token=cfg.bot_token)
# closure captures slack_client
```

No interface change to `get_mcp_servers()` is needed.

**Test**: `test_fetch_channel_history_tool_round_trip` — mock
`conversations_history` to return two messages; call the tool; assert both
rows appear in `slack_messages`; call again with same mock; assert row count
is still 2 (idempotent).

---

### 4. Extend `_build_system_prompt()` with DB one-liner knowledge

**File**: `pykoclaw-slack/src/pykoclaw_slack/connection.py`
**Method**: `_build_system_prompt()`

Add at the end of the returned string (after the name-variation paragraph):

```python
db_path = core_settings.db_path  # already imported as `from pykoclaw.config import settings as core_settings`
```

```
Message database: {db_path} (SQLite, WAL mode — safe for concurrent reads)
Tables:
  slack_messages(id, channel_id, sender, text, timestamp, slack_ts,
                 thread_ts, is_from_me, attachment_path)
  slack_channels(channel_id, name, last_timestamp, last_agent_timestamp)

To search messages (read-only, any SQL):
  python3 -c "import sqlite3; [print(r) for r in sqlite3.connect('file:{db_path}?mode=ro', uri=True).execute(\"SELECT channel_id, sender, timestamp, text FROM slack_messages WHERE text LIKE '%keyword%' ORDER BY timestamp DESC LIMIT 20\").fetchall()]"

To search a specific channel or thread, add AND channel_id = 'C...' or AND thread_ts = '...' to the WHERE clause.
Use fetch_channel_history first if you need messages from a channel not yet in the local DB.
```

The f-string interpolates `db_path` once at prompt-build time so the agent
always gets a fully-resolved absolute path.

**Gotcha — session resume**: From the CLAUDE.md gotcha, `system_prompt` is
ignored on session resume. This is acceptable for reference knowledge: the
agent learns the DB path and schema on the _first turn_ of a new session and
retains it through conversation history. Per-turn directives (must reply,
must use `<reply>` tags) already live in the _user prompt_ for this reason;
DB reference info is correctly placed in the system prompt.

**No test required** — the system prompt is a pure string; the format_xml
tests already cover the surrounding context.

---

## Required Slack OAuth Scopes

| Scope              | Needed for                                           | Likely already granted? |
| ------------------ | ---------------------------------------------------- | ----------------------- |
| `channels:history` | `conversations.history` on public channels           | ✓ Almost certainly      |
| `groups:history`   | `conversations.history` on private channels          | May need adding         |
| `channels:read`    | Resolving channel names in search results (optional) | Likely yes              |

If `groups:history` is missing, `fetch_channel_history` will return
`"missing_scope"` from the Slack API for private channels; the error message
in the tool response is human-readable and self-explanatory.

---

## File Changeset

| File                                              | Change                                                             |
| ------------------------------------------------- | ------------------------------------------------------------------ |
| `pykoclaw-slack/src/pykoclaw_slack/__init__.py`   | Unique index migration; `fetch_channel_history` tool               |
| `pykoclaw-slack/src/pykoclaw_slack/handler.py`    | `store_messages_from_api()`; add `datetime`/`timezone` imports     |
| `pykoclaw-slack/src/pykoclaw_slack/connection.py` | Extend `_build_system_prompt()` with DB path + schema + one-liner  |
| `pykoclaw-slack/tests/test_handler.py`            | Tests for `store_messages_from_api` (idempotence, partial overlap) |
| `pykoclaw-slack/tests/test_slack_plugin.py`       | Test for unique index migration; tool round-trip test              |

No changes outside `pykoclaw-slack`. No new dependencies. No changes to
`pykoclaw`, `pykoclaw-messaging`, or any other workspace member.

---

## Verification Strategy

### Unit tests

```bash
cd ~/pykoclaw-dev/<worktree>
uv run pytest pykoclaw-slack/tests/ -v -k "unique_index or store_messages or fetch_channel"
```

### Manual QA

1. Start the Slack listener in a testi environment.
2. Ask the agent: "Search for messages about deployments in #general."
   - Verify it generates a one-liner and executes it via Bash.
   - Verify the result is a sensible set of messages.
3. Ask the agent: "Fetch the last 50 messages from #random."
   - Verify `fetch_channel_history` is called.
   - Verify the XML block is returned.
   - Call again — verify the summary shows `0 new rows inserted`.
4. Ask for messages from a channel the bot has never been in.
   - Verify the API error is surfaced as a human-readable string.

---

## Non-Goals (explicit)

- **Full Slack workspace `search.messages` API** — requires a _user token_
  with `search:read` scope (bot tokens are ineligible). Not worth the extra
  OAuth complexity given `conversations.history` + local SQL covers 95% of
  real search use cases.
- **FTS5 virtual table** — `LIKE` is sufficient for typical keyword search.
  A FTS5 migration can be added later as a separate backlog item if query
  speed on large tables becomes an issue.
- **Joining channels on behalf of the agent** — out of scope; the bot must
  already be a member.
- **Pagination across multiple `conversations.history` pages** — the 200-
  message cap in the tool is a practical upper bound. Full-history sync of
  large channels can be done by the agent issuing multiple calls with the
  `oldest`/`latest` range parameters.
