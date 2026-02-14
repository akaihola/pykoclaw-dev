# Telegram Markdown & Tables Integration Plan

**Context:** Nanobot's `_markdown_to_telegram_html()` handles basic formatting but **no tables** — they pass through raw Markdown `| col |` and render poorly on Telegram mobile.

**Upstream status:** [HKUDS/nanobot#559](https://github.com/HKUDS/nanobot/issues/559) - "Slack doesn't support full markdown -e.g. tables" — open since 2026-02-12, no PR yet.

---

## Solution: `telegramify-markdown` Library

**Package:** `telegramify-markdown` ([PyPI](https://pypi.org/project/telegramify-markdown/), [GitHub](https://github.com/sudoskys/telegramify-markdown))

**How it works:**
- Converts full Markdown → Telegram `MarkdownV2` format
- Returns `(text, entities)` tuple for native Bot API
- No `parse_mode` needed — uses entity arrays

**Key features:**
| Feature | Support |
|---------|---------|
| Tables `\| col \| col \|` | ✅ Converts to aligned monospaced text |
| Headers `# H1` | ✅ Emoji prefixes + bold |
| Bold, italic, code, links | ✅ Full GitHub-flavored |
| Code blocks | ✅ Preserved |

**Usage:**
```python
from telegramify_markdown import convert

text, entities = convert(markdown_content)
bot.send_message(chat_id, text, entities=entities)
```

---

## Integration Plan for pykoclaw

### Option A: Add to `pykoclaw-messaging` (Recommended)

Create shared formatting module used by all channel plugins:

```
pykoclaw-messaging/
├── src/
│   └── pykoclaw_messaging/
│       ├── __init__.py
│       ├── dispatch.py
│       └── format.py          # ← NEW: telegramify-markdown wrapper
```

**`format.py`:**
```python
"""Shared message formatting for all channels."""

from typing import Literal
import telegramify_markdown


def format_message(
    content: str,
    target: Literal["telegram", "whatsapp"],
) -> tuple[str, list[dict] | None]:
    """
    Format Markdown content for target channel.
    
    Returns:
        (text, entities) for Telegram, (text, None) for WhatsApp
    """
    if target == "telegram":
        text, entities = telegramify_markdown.convert(content)
        return text, entities
    
    # WhatsApp: plain text with simple Markdown-ish formatting
    # (WhatsApp doesn't support entities API, uses *bold* _italic_ syntax)
    return _format_whatsapp(content), None


def _format_whatsapp(text: str) -> str:
    """Minimal formatting for WhatsApp (bold, italic, strikethrough)."""
    # Tables → bullet lists for WhatsApp
    # ... implementation ...
    pass
```

### Option B: New `pykoclaw-formatting` Package

If formatting logic grows complex:

```
pykoclaw/
├── pykoclaw-formatting/       # ← NEW package
│   ├── pyproject.toml
│   └── src/
│       └── pykoclaw_formatting/
│           ├── telegram.py    # telegramify-markdown wrapper
│           ├── whatsapp.py    # WhatsApp-style formatting
│           └── tables.py      # Table → bullets conversion
```

**Pros:** Cleaner separation, can evolve independently  
**Cons:** More packages to maintain

---

## Implementation Steps

1. **Add dependency** to `pykoclaw-messaging/pyproject.toml`:
   ```toml
   dependencies = [
       "pykoclaw",
       "telegramify-markdown>=0.5.0",
   ]
   ```

2. **Create `format.py`** with `telegramify_markdown.convert()` wrapper

3. **Update pykoclaw-telegram** (when created) to use new formatter:
   ```python
   from pykoclaw_messaging.format import format_message
   
   text, entities = format_message(content, "telegram")
   bot.send_message(chat_id, text, entities=entities)
   ```

4. **Update pykoclaw-whatsapp** to use bullet-style table fallback

---

## Comparison: telegramify-markdown vs Native HTML

| Approach | Tables | Pros | Cons |
|----------|--------|------|------|
| **Current** `_markdown_to_telegram_html()` | ❌ Raw `\| col \|` | Simple, no deps | Tables broken |
| **telegramify-markdown** | ✅ Aligned monospaced | Full Markdown support, maintained | New dependency |
| **MiniApp** | ✅ Full HTML | Perfect rendering | Overkill, requires hosting |

**Recommendation:** `telegramify-markdown` — best balance of functionality and simplicity.

---

## Future: pykoclaw-telegram Channel

When implementing Telegram support in pykoclaw:

```python
# In pykoclaw-telegram/src/pykoclaw_telegram/handler.py
from telegramify_markdown import convert
from telegram import Bot

async def send_response(chat_id: int, markdown_content: str) -> None:
    text, entities = convert(markdown_content)
    await bot.send_message(chat_id, text, entities=entities)
```

**Benefit:** Same formatting logic can serve both Nanobot-style usage and pykoclaw plugins.

---

## References

- **telegramify-markdown:** https://github.com/sudoskys/telegramify-markdown
- **Nanobot issue #559:** https://github.com/HKUDS/nanobot/issues/559
- **Telegram Bot API:** https://core.telegram.org/bots/api#formatting-options
