# Telegram Markdown Table Rendering Research

**Date:** 2026-02-16  
**Context:** Nanobot Markdown tables render poorly on Telegram (unaligned raw text). Research solutions for pykoclaw-telegram.

---

## The Problem

Telegram Bot API does **not support native tables**. Markdown `| col |` syntax:
- Passes through as raw text
- Loses column alignment (font-dependent)
- Hard to read on mobile

---

## Option C: telegramify-markdown Library

**Library:** `sudoskys/telegramify-markdown` (PyPI)

**What it does:**
- Converts full GitHub-flavored Markdown to Telegram's native entity format
- Tables → **monospaced aligned text blocks** (not true UI tables)
- Returns `(text, entities)` tuple for Bot API

**Pros:**
- ✅ Handles all Markdown (bold, italic, code, links, tables)
- ✅ Actively maintained
- ✅ No `parse_mode` needed — uses native entities
- ✅ Same library can serve WhatsApp (text fallback)

**Cons:**
- ❌ Still no true table UI — just monospace alignment
- ❌ New dependency

**Usage:**
```python
from telegramify_markdown import convert

text, entities = convert("| Date | BP |\n|------|-----|\n| Feb 14 | 141/86 |")
# Result: monospaced block with aligned columns
bot.send_message(chat_id, text, entities=entities)
```

---

## Option D: Telegram MiniApp (WebApp)

**What it is:** HTML/CSS/JS app running inside Telegram

**For tables:**
- Full HTML `<table>` support
- Rich styling, interactive elements

**Flow:**
```
Bot sends button → "Open App" → MiniApp renders table
                      ↓
              User clicks "Send result"
                      ↓
              Back to chat with data
```

**Pros:**
- ✅ Perfect table rendering
- ✅ Interactive features
- ✅ Any HTML/CSS/JS

**Cons:**
- ❌ Overkill for simple tables
- ❌ Requires hosting
- ❌ User must click to open
- ❌ Complex for basic use cases

---

## Recommendation for pykoclaw-telegram

**Use telegramify-markdown (Option C)** in shared `pykoclaw-messaging` module.

**Rationale:**
1. Monospace tables are acceptable for most use cases
2. Same formatting logic serves both Telegram (entities) and WhatsApp (text)
3. MiniApp complexity only justified for interactive dashboards

**Implementation:**
- Add `telegramify-markdown>=0.5.0` to dependencies
- Create `format.py` wrapper with platform detection
- Telegram: `convert()` → `(text, entities)`
- WhatsApp: `convert()` → extract text only

---

## References

- https://github.com/sudoskys/telegramify-markdown
- https://core.telegram.org/bots/webapps (MiniApp docs)
- Nanobot issue #559 (no table support)
