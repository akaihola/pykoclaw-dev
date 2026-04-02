# Slack Entity Resolution — Human-Readable Channel and User Names

## Status: Done

## Completed: 2026-03-25

## TL;DR

> **User experience problem**: The bot outputs raw Slack IDs like `#C0AHUPS69QF`
> instead of `#general` when referring to channels, and `<@U12345678>` instead
> of `@Alice`. This is because inbound Slack message text contains encoded
> entity references (`<#C…>`, `<@U…>`) which are stored and forwarded to Claude
> as-is. Claude then echoes these opaque IDs in its replies.
>
> **Solution**: Decode Slack entity references to human-readable names on the
> inbound side (before the agent sees them), and maintain a channel directory
> so the agent can refer to channels by name proactively.
>
> **Deliverables**:
>
> - `resolver.py`: New module with `SlackEntityResolver` class — cached
>   user/channel/usergroup name resolution via `slack-sdk` API calls
> - `connection.py`: Integrate resolver into `_handle_message()` to decode
>   inbound text before storage and prompting
> - `connection.py`: Inject a channel directory snippet into the system prompt
> - Tests for the resolver and the decode pipeline
>
> **Estimated Effort**: Medium (2–4 hours)
> **Parallel Execution**: NO — resolver first, then integration, then tests
> **Critical Path**: Resolver module → inbound integration → system prompt →
> tests
>
> Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-25T08-00-06-152Z_0bd7f9e0-79c3-4c4f-b0ab-a4f8063d8c2c.jsonl

---

## Context

### The Problem

Slack's API delivers message text with [special encoded references][slack-formats]:

| Pattern                                | Meaning               | Example raw text              |
| -------------------------------------- | --------------------- | ----------------------------- |
| `<#C0AHUPS69QF>` or `<#C…\|name>`      | Channel link          | "check `<#C0AHUPS69QF>`"      |
| `<@U12345678>` or `<@U…\|name>`        | User mention          | "`<@U12345678>` said…"        |
| `<!subteam^S123\|@team>`               | Usergroup mention     | "cc `<!subteam^S123\|@devs>`" |
| `<!here>`, `<!channel>`, `<!everyone>` | Broadcast mentions    | "`<!here>` heads up"          |
| `<http://…\|text>`                     | URL with display text | "`<http://x.com\|link>`"      |

Additionally, `&amp;`, `&lt;`, `&gt;` HTML entities appear in raw text.

Currently `pykoclaw-slack` stores and forwards these raw strings to Claude,
which has no way to resolve `C0AHUPS69QF` → `general`. It then echoes the IDs.

### Comparison with Other Channel Plugins

**pykoclaw-matrix** resolves user IDs to display names in `connection.py`:

```python
display_name = room.user_name(sender) or sender
```

**pykoclaw-slack** passes raw `event["user"]` (a Slack user ID like `U12345`)
as the sender, never resolving it.

### Competitor Research

#### Hermes Agent (NousResearch/hermes-agent)

Hermes has a mature **two-layer approach**:

1. **User name resolution** (`SlackAdapter._resolve_user_name()`): On each
   incoming message, resolves the sender's `user_id` to a display name via
   `users.info` with an in-memory `_user_name_cache: Dict[str, str]`.
   Priority: `display_name` → `real_name` → `user.name` → raw ID.

2. **Channel directory** (`gateway/channel_directory.py`): A persistent
   `~/.hermes/channel_directory.json` built at startup and refreshed every
   5 minutes. Maps channel IDs to names across all platforms. The
   `send_message` tool's `action="list"` reads this file, and
   `resolve_channel_name()` does case-insensitive lookup with partial-prefix
   fallback. The directory is built from Slack API calls
   (`conversations.list`) and supplemented by session history for platforms
   that can't enumerate channels.

3. **No inbound text decoding**: Hermes does NOT decode `<#C…>` / `<@U…>`
   references inside message text bodies. It strips only the bot's own
   `<@BOT_ID>` mention. This means Hermes has the same raw-ID-in-text
   problem we do — a gap we can do better on.

#### Nanobot (HKUDS/nanobot)

Nanobot's Slack channel (`nanobot/channels/slack.py`) is simpler:

1. Uses `slack-sdk` directly (not `slack-bolt`) with Socket Mode.
2. Strips the bot's own `<@BOT_ID>` mention from text.
3. **No user name resolution** — passes raw `sender_id` through.
4. **No entity decoding** — `<#C…>` references pass through untouched.
5. **No channel directory** — no cross-channel `send_message` tool.

Both competitors have this gap. Our implementation will be strictly better.

### PyPI Package Landscape

No standalone PyPI package exists for decoding inbound Slack entity references.
The relevant packages:

| Package              | Role                                                                                     | Useful here?                                                       |
| -------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `slack-sdk` (3.40+)  | Official SDK with `users.info`, `conversations.info`, `users.list`, `conversations.list` | Yes — provides all API calls needed                                |
| `slack-bolt` (1.27+) | App framework (already used) — no built-in entity resolution                             | Already a dependency                                               |
| `slackify-markdown`  | Markdown → mrkdwn (already used for outbound)                                            | Not relevant (wrong direction)                                     |
| `cachetools`         | TTL-aware caches                                                                         | Candidate for TTL cache, but `dict` + startup prefetch may suffice |

**Conclusion**: No package helps with the decode step. It's a ~30-line regex
function plus API calls we already have access to. `slack-sdk` (already an
indirect dependency via `slack-bolt`) provides all the resolution APIs.

---

## Design

### Architecture

```
Inbound:  Slack event → decode_slack_text() → store_message() → XML prompt
                              ↓
                    SlackEntityResolver (cached lookups)
                              ↓
                    users.info / conversations.info (on cache miss)
```

### SlackEntityResolver

A class attached to `SlackConnection` that:

1. **Prefetches** users and channels at startup via `users.list` /
   `conversations.list` (paginated, bulk — Tier 2 rate limit, ~20 req/min).
2. **Caches** in simple `dict[str, str]` maps (`_users`, `_channels`,
   `_usergroups`). No TTL needed — refresh the full cache every N minutes
   in the background (like Hermes's 5-minute refresh).
3. **Falls back** to on-demand `users.info` / `conversations.info` on cache
   miss, then caches the result.
4. **Decodes** message text by replacing `<…>` patterns with resolved names.

### Decode Algorithm

Following the [official Slack documentation][slack-formats]:

```python
def decode_slack_text(self, text: str) -> str:
    # 1. Unescape HTML entities
    text = text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    # 2. Replace <…> patterns
    return re.sub(r"<([^>]+)>", self._replace_entity, text)

def _replace_entity(self, match: re.Match) -> str:
    inner = match.group(1)
    # Split on pipe — Slack sometimes includes a fallback label
    pipe_pos = inner.find("|")
    fallback = inner[pipe_pos + 1:] if pipe_pos != -1 else None
    entity = inner[:pipe_pos] if pipe_pos != -1 else inner

    if entity.startswith("#C"):
        return "#" + self._resolve_channel(entity[1:], fallback)
    if entity.startswith("@U") or entity.startswith("@W"):
        return "@" + self._resolve_user(entity[1:], fallback)
    if entity.startswith("!subteam^"):
        return "@" + (fallback or "team")
    if entity in ("!here", "!channel", "!everyone"):
        return "@" + entity[1:]
    # URL — use fallback text if available, else the URL
    return fallback or entity
```

### Sender Name Resolution

Currently `event["user"]` (e.g. `U12345678`) is stored as the sender. Resolve
it to a display name before `store_message()` and `format_xml_message()`, same
as Hermes does. Fall back to the raw ID if resolution fails.

### System Prompt Channel Directory

At startup (and on periodic refresh), inject a small channel listing into the
system prompt so the agent can refer to channels by name when composing
messages or discussing workspace layout:

```
## Known Slack channels
#general, #random, #engineering, #design, …
```

Keep it compact (just names, no IDs). The agent doesn't need IDs — it replies
via `<reply>` tags into the current channel. If we later add a `send_message`
MCP tool that accepts channel names, the resolver can map names back to IDs.

---

## Tasks

### 1. Create `resolver.py` — SlackEntityResolver

**File**: `pykoclaw-slack/src/pykoclaw_slack/resolver.py`

- `SlackEntityResolver` class with:
  - `__init__(self, client: AsyncWebClient)` — stores client ref, empty caches
  - `async prefetch(self)` — bulk-loads users, channels, usergroups via
    paginated `users.list`, `conversations.list`, `usergroups.list`
  - `async refresh(self)` — re-runs `prefetch()` (called periodically)
  - `decode_text(self, text: str) -> str` — synchronous regex-based decoder
    using cached data only (no API calls — fast path)
  - `async resolve_user(self, user_id: str) -> str` — cache lookup, fallback
    to `users.info` API call
  - `async resolve_channel(self, channel_id: str) -> str` — cache lookup,
    fallback to `conversations.info` API call
  - `get_channel_names(self) -> list[str]` — returns sorted list of all known
    channel names (for system prompt)
- Caches: `_users: dict[str, str]`, `_channels: dict[str, str]`,
  `_usergroups: dict[str, str]`
- User name priority (matching Hermes): `display_name` → `real_name` →
  `user.name` → raw ID
- The `decode_text()` method is synchronous and uses only cached data so it
  can be called in the hot path without awaiting. Cache misses in message
  text are left as fallback labels or raw IDs — they'll resolve on the next
  refresh cycle. The async `resolve_user()` is used separately for the
  sender field where we can afford to await.
- Required OAuth scopes: `users:read`, `channels:read`, `groups:read`,
  `usergroups:read`

### 2. Integrate resolver into `SlackConnection`

**File**: `pykoclaw-slack/src/pykoclaw_slack/connection.py`

- In `run_async()`, after `auth_test()`:
  - Create `self._resolver = SlackEntityResolver(self._app.client)`
  - `await self._resolver.prefetch()`
  - Start a background `asyncio.Task` that calls `self._resolver.refresh()`
    every 5 minutes (same cadence as Hermes)
- In `_handle_message()`:
  - Decode `text` via `self._resolver.decode_text(text)` before storing
  - Resolve `user` to display name via `await self._resolver.resolve_user(user)`
    before passing to `store_message()` as `sender`
- In `_build_system_prompt()`:
  - Append a `## Known Slack channels` section with
    `self._resolver.get_channel_names()` (comma-separated, compact)

### 3. Resolve sender names in message XML

**File**: `pykoclaw-slack/src/pykoclaw_slack/handler.py`

The `format_xml_message()` function already takes `sender` as a parameter.
No changes needed here — the fix is upstream in `_handle_message()` where
we pass the resolved name instead of the raw ID.

Verify that `store_message()` stores the resolved name (not the raw ID) so
historical messages also show readable names in the XML context.

### 4. Add tests

**File**: `pykoclaw-slack/tests/test_resolver.py`

- **Unit tests for `decode_text()`**: Cover all entity types:
  - `<#C123ABC>` → `#general` (cached)
  - `<@U123ABC>` → `@Alice` (cached)
  - `<@U123ABC|alice>` → `@Alice` (pipe fallback)
  - `<!here>` → `@here`
  - `<!channel>` → `@channel`
  - `<!subteam^S123|@devs>` → `@devs`
  - `<http://example.com|Example>` → `Example`
  - `<http://example.com>` → `http://example.com`
  - HTML entities: `&amp;` → `&`, `&lt;` → `<`, `&gt;` → `>`
  - Mixed: `<@U1> said check <#C2> and <http://x.com|this>`
  - Unknown/uncached channel ID: falls back to raw ID or pipe label
- **Unit tests for `resolve_user()`**: mock `users.info`, verify caching
- **Integration test**: feed a Slack event with encoded text through
  `_handle_message()`, verify the stored message has decoded text

### 5. Verify OAuth scopes

Check that the bot's OAuth scopes in the Slack app configuration include
`users:read`, `channels:read`, `groups:read`. If `usergroups:read` is
missing, the usergroup resolution gracefully degrades (logs a warning,
skips prefetch). Document required scopes in `pykoclaw-slack/README.md`.

---

## Non-Goals (Explicitly Out of Scope)

- **Outbound re-encoding**: We don't need to convert `#general` back to
  `<#C123|general>` in outbound messages. Slack renders plain `#general` as
  readable text (though not as a clickable link). If clickable channel links
  become important, that's a separate enhancement.
- **Full channel directory for cross-channel messaging**: The `send_message`
  MCP tool currently only routes to the delivery queue by channel ID. Adding
  name-based routing (like Hermes's `resolve_channel_name()`) is a separate
  backlog item.
- **User presence / online status**: Not needed for name resolution.

---

## Risks & Mitigations

| Risk                                                 | Mitigation                                                                   |
| ---------------------------------------------------- | ---------------------------------------------------------------------------- |
| `users.list` hitting rate limits on large workspaces | Paginate with cursor; Tier 2 allows ~20 req/min; cache aggressively          |
| Bot lacks `users:read` or `channels:read` scope      | Graceful degradation — log warning, fall back to raw IDs; document in README |
| Cache staleness (new channel created after prefetch) | 5-minute refresh cycle + on-demand fallback for cache misses                 |
| `decode_text()` performance on hot path              | Synchronous regex on cached dict — sub-millisecond; no API calls             |

[slack-formats]: https://api.slack.com/reference/surfaces/formatting#retrieving-messages
