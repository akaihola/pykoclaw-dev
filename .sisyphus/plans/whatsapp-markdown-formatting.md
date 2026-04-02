# WhatsApp Markdown Formatting

## Status: Done

## Completed: 2026-02-22

## TL;DR

> **Quick Summary**: Add a Markdown → WhatsApp markup converter in `pykoclaw-whatsapp`
> so agent replies render nicely in WhatsApp instead of leaking raw Markdown syntax.
> Mirror the same pattern already used in `pykoclaw-matrix/formatting.py`.
>
> **Deliverables**:
>
> - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/formatting.py` — the converter
> - Integration in `connection.py`: apply formatter before sending
> - Comprehensive test suite in `pykoclaw-whatsapp/tests/test_formatting.py`
> - `markdown-it-py` added to `pykoclaw-whatsapp` dependencies
>
> **Estimated Effort**: Medium (a day or two)
> **Parallel Execution**: NO — sequential (formatter first, then integration, then tests)
> **Critical Path**: Task 1 → Task 2 → Task 3

---

## Context

### What WhatsApp actually supports

Based on user testing + research (Feb 2026):

| Works ✅                   | Does NOT work ❌              |
| -------------------------- | ----------------------------- |
| `*bold*`                   | `# ## ###` headings           |
| `_italic_`                 | `---` horizontal rule         |
| `~strikethrough~`          | Nested lists (ignored)        |
| `` `monospace` ``          | `- [ ]` / `- [x]` checkboxes  |
| ` ``` `code block` ``` `   | Language-tagged fenced blocks |
| `- bullet list`            | `[text](url)` links           |
| `1. numbered list`         | HTML tags                     |
| `> blockquote`             | Tables                        |
| Combined `*_bold italic_*` |                               |

WhatsApp has **no HTML support** — unlike Matrix which accepts
`org.matrix.custom.html`. Everything must be expressed in WhatsApp's own
markup tokens.

### How Matrix does it (the model to follow)

`pykoclaw-matrix/formatting.py` uses `markdown-it-py` (CommonMark parser) to
produce HTML. We use the same library but walk the token stream differently to
produce WhatsApp text. Both formatters live in their own package — no shared
code needed since the output formats are completely different.

---

## Conversion strategy (all decisions locked)

### Direct mappings (pass-through)

| Markdown            | WhatsApp          | Notes                        |
| ------------------- | ----------------- | ---------------------------- |
| `**bold**`          | `*bold*`          | Also handles `__bold__`      |
| `*italic*`          | `_italic_`        | Also handles `_italic_`      |
| `~~strikethrough~~` | `~strikethrough~` |                              |
| `` `code` ``        | `` `code` ``      | Pass-through                 |
| ` ``` `…` ``` `     | ` ``` `…` ``` `   | Strip language label (see §) |
| `- item`            | `- item`          | Pass-through                 |
| `1. item`           | `1. item`         | Pass-through                 |
| `> quote`           | `> quote`         | Pass-through                 |

### Headings → bold with decorative underline

One blank line **before** every heading (separates from preceding content).
After the heading content:

- **H1**: the underline row `▔▔▔…` is emitted immediately after the bold
  text, with **no blank line after** — `▔` (U+2594 UPPER ONE EIGHTH BLOCK)
  sits at the top 1/8 of its cell and provides sufficient visual gap on its
  own.
- **H2 / H3**: one blank line after (no underline to provide that space).

| Markdown    | WhatsApp output                                      |
| ----------- | ---------------------------------------------------- |
| `# Title`   | `*TITLE*` + newline + 27 × `▔` — no blank line after |
| `## Title`  | `*TITLE*` (all caps, bold) + blank line after        |
| `### Title` | `*Title*` (title-cased, bold) + blank line after     |

Module-level constants:

```python
HEADING_RULE_CHAR = "\u2594"  # ▔ UPPER ONE EIGHTH BLOCK
HEADING_RULE_LEN = 27
```

The underline is only applied to H1; H2 and H3 convey hierarchy through
all-caps / capitalisation alone.

### Horizontal rule (`---` / `***` / `___`)

Emit 27 × `─` (U+2500 BOX DRAWINGS LIGHT HORIZONTAL) — mid-height, visually
distinct from the H1 `▔` overline. Surrounded by blank lines.

### Lossy / approximated mappings

| Markdown construct         | WhatsApp approximation                     | Rationale                         |
| -------------------------- | ------------------------------------------ | --------------------------------- |
| Nested `- sub` (depth 2+)  | `  • sub` (2-space + U+2022 bullet)        | WA ignores indent; emoji survives |
| Deeper nesting (depth 3+)  | `    • sub` (4-space + bullet)             | Each level adds 2 spaces          |
| `- [ ] task`               | `⬜ task`                                  | Emoji fallback                    |
| `- [x] task`               | `✅ task`                                  | Emoji fallback                    |
| `[text](url)` (text ≠ url) | `text (url)`                               | No clickable link syntax          |
| `[url](url)` / bare URL    | `url`                                      | WA auto-links bare URLs           |
| Markdown table             | Unicode box table in ` ``` ` fence (see §) | Preserves alignment               |
| `![alt](path)`             | _(strip — image sent separately)_          | `split_segments` handles images   |

### Unicode box tables

Column widths computed from the widest cell in each column. Full border with
box-drawing chars. Header separated by `├─┼─┤` divider. Wrapped in a
` ``` ` monospace fence so WhatsApp preserves spacing (monospace font).

Characters used: `┌ ─ ┬ ┐ │ ├ ┼ ┤ └ ┴ ┘`

Example:

```
┌──────────┬────────┐
│ Name     │ Score  │
├──────────┼────────┤
│ Alice    │ 42     │
│ Bob      │ 17     │
└──────────┴────────┘
```

### Code block language labels

` ```python` shows `python` as the first monospace line — ugly. Strip it:

Before: ` ```python` → After: ` ``` ` (language info discarded, code preserved)

---

## Implementation notes

### Token-stream approach

Use `MarkdownIt("commonmark").parse(text)` which returns a flat list of block
tokens. Each block token optionally has `children` (inline tokens). Walk blocks
with a `_render_block(tokens)` function, dispatch on `token.type`:

```
bullet_list_open / ordered_list_open
  list_item_open
    inline → children
  list_item_close
bullet_list_close / ordered_list_close

heading_open (tag="h1"/"h2"/"h3")
  inline → children
heading_close

fence (code block — attrs carry language)
code_inline

hr

blockquote_open
  ...
blockquote_close

table_open
  thead_open → tr → th cells
  thead_close
  tbody_open → tr → td cells
  tbody_close
table_close

inline → children
  softbreak / hardbreak
  strong_open / strong_close
  em_open / em_close
  s_open / s_close (strikethrough)
  code_inline
  image (strip)
  link_open / link_close
  text
```

Keep a stack of open contexts (list depth, blockquote depth) so nested
structures emit correct indentation.

### Blank-line enforcement

- Before any heading or hr: ensure exactly one blank line (strip trailing
  whitespace from previous output, append `\n\n`).
- After H2 / H3: append `\n\n`.
- After H1 underline row: append `\n` only (no blank line — the `▔`
  character's top-positioned glyph provides visual separation).
- After hr: append `\n\n`.

### Public API

```python
HEADING_RULE_CHAR = "\u2594"  # ▔ UPPER ONE EIGHTH BLOCK
HEADING_RULE_LEN = 27

def markdown_to_whatsapp(text: str) -> str:
    """Convert Markdown text to WhatsApp-native markup.

    Handles: bold, italic, strikethrough, inline code, fenced code blocks
    (language label stripped), bullet/numbered lists, nested lists (bullet
    emoji), task lists (emoji checkboxes), blockquotes, headings (H1/H2
    all-caps bold + H1 decorative underline, H3 bold), horizontal rules
    (unicode line), links (text (url) or bare url), tables (unicode box
    in monospace fence), images (stripped).
    """
```

---

## Tasks

### Task 1 — `formatting.py` module

File: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/formatting.py`

Implement `markdown_to_whatsapp()` as described above. Add `markdown-it-py`
and `mdit-py-plugins` to `pykoclaw-whatsapp/pyproject.toml` dependencies
(matrix plugin already pulls them into the workspace).

Enable strikethrough: `MarkdownIt("commonmark").enable("strikethrough")`.
Also enable `tasklists_plugin` from `mdit-py-plugins` so `- [ ]` / `- [x]`
tokens are recognised (same as Matrix formatter).

### Task 2 — Integration in `connection.py`

Apply the formatter at exactly two call sites:

1. `_dispatch_for_agent()` — agent replies:

```python
from .formatting import markdown_to_whatsapp

extracted = _extract_reply(result.full_text)
if extracted:
    extracted = markdown_to_whatsapp(extracted)
    ...
```

2. `_process_deliveries_from_db()` — scheduled task deliveries:

```python
message = markdown_to_whatsapp(delivery.message)
```

### Task 3 — Tests

File: `pykoclaw-whatsapp/tests/test_formatting.py`

Parametrised pytest cases for every mapping in the conversion table:

- Bold, italic, strikethrough, inline code (pass-through)
- Fenced block without language label (pass-through)
- Fenced block WITH language label (label stripped)
- `# H1` → all-caps bold + 27 × `▔` underline, no blank line after rule
- `## H2` → all-caps bold, no underline, blank line after
- `### H3` → title-case bold, no underline, blank line after
- `---` hr → 27 × `─`, surrounded by blank lines
- `- item` bullet list
- `1. item` numbered list
- Nested list depth 2 (→ `  • sub`)
- Nested list depth 3 (→ `    • sub`)
- `- [ ] task` → `⬜ task`
- `- [x] task` → `✅ task`
- `[text](url)` → `text (url)`
- `[url](url)` bare link → `url`
- Markdown table → unicode box table wrapped in ` ``` `
- `![alt](path)` → stripped (image handled separately)
- Combined styles `**_bold italic_**`
- Empty input → empty string
- Plain text (no Markdown) → unchanged
- Multiple headings in sequence (correct blank-line separation for each level)

Run from worktree root:

```bash
cd /home/agent/prg/pykoclaw-worktrees/whatsapp-markdown
uv run pytest pykoclaw-whatsapp/tests/test_formatting.py -v
```

---

## Non-goals

- No Matrix-side changes (already working perfectly).
- No changes to the agent system prompt to constrain Markdown output
  (fragile; better to convert everything robustly).
- No table-to-image rendering (requires Playwright/Pillow — too heavy).
- No passthrough config flag (not needed).
- No support for WhatsApp GUI-only formatting (menu-applied styles not
  available via the API).
