# Dynamic Channel Prefix Discovery

## Status: Backlog
## Priority: 3

## TL;DR

> **Quick Summary**: Replace the hardcoded `KNOWN_CHANNEL_PREFIXES` frozenset
> in `db.py` with dynamic discovery from installed plugins. Each channel plugin
> declares a `channel_prefixes` class attribute; the core collects them at
> startup via `load_plugins()`. This makes cross-agent delivery work
> automatically with future channel plugins (e.g. Slack, Telegram) without
> touching core code.
>
> **Deliverables**:
> - `plugins.py`: Add `channel_prefixes: frozenset[str]` to `PykoClawPlugin` protocol and `PykoClawPluginBase` (default `frozenset()`)
> - `plugins.py`: Add `collect_channel_prefixes(plugins)` function
> - `db.py`: Remove `KNOWN_CHANNEL_PREFIXES` constant; `has_known_channel_prefix()` takes or reads a collected set
> - Channel plugins: Add `channel_prefixes` class attribute to `WhatsAppPlugin` (`{"wa"}`), `MatrixPlugin` (`{"matrix"}`), `AcpPlugin` (`{"acp"}`), `ChatPlugin` (`{"chat"}`)
> - Tests: Verify prefix collection from plugins, verify `resolve_delivery_target()` still works
>
> **Estimated Effort**: Quick (< 1 hour)
> **Parallel Execution**: NO — protocol change first, then plugin updates, then core removal
> **Critical Path**: Protocol change → plugin attributes → core removal → tests

---

## Context

### Original Request

`KNOWN_CHANNEL_PREFIXES` in `db.py` is a hardcoded frozenset:

```python
KNOWN_CHANNEL_PREFIXES: frozenset[str] = frozenset(
    {"wa", "acp", "matrix", "tg", "chat"}
)
```

This is used by `has_known_channel_prefix()`, which `resolve_delivery_target()`
in `scheduler.py` calls to decide whether a `target_conversation` value is
already fully qualified or needs prefix inheritance. If a new channel plugin
(e.g. Slack) isn't added to this set, cross-agent delivery silently mangles the
conversation name.

### Design Decision

Use **discovery over registration**: plugins declare their prefix as a class
attribute (not a `register_channel_prefix()` call), and the core collects them
from all installed plugins at startup. This avoids import-order issues and
forgotten registration calls.

Class attribute (not `@property`) because prefixes are static per plugin class —
no runtime computation needed.

---

## Tasks

### 1. Add `channel_prefixes` to protocol and base class

**File**: `pykoclaw/src/pykoclaw/plugins.py`

Add `channel_prefixes: frozenset[str]` to the `PykoClawPlugin` protocol.
Add default `channel_prefixes: frozenset[str] = frozenset()` to `PykoClawPluginBase`.
Add `collect_channel_prefixes()` helper.

### 2. Declare prefixes on channel plugins

**Files**:
- `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py` → `frozenset({"wa"})`
- `pykoclaw-matrix/src/pykoclaw_matrix/__init__.py` → `frozenset({"matrix"})`
- `pykoclaw-acp/src/pykoclaw_acp/__init__.py` → `frozenset({"acp"})`
- `pykoclaw-chat/src/pykoclaw_chat/__init__.py` → `frozenset({"chat"})`

### 3. Wire collection into startup and replace hardcoded set

**Files**: `pykoclaw/src/pykoclaw/db.py`, `pykoclaw/src/pykoclaw/__main__.py`

Remove `KNOWN_CHANNEL_PREFIXES`. Make `has_known_channel_prefix()` use the
collected set (either passed as argument or set once at module level during
startup after `load_plugins()` runs).

### 4. Update tests

Ensure `test_delivery.py` still passes. Add a unit test for
`collect_channel_prefixes()` and for `has_known_channel_prefix()` with
dynamically collected prefixes.
