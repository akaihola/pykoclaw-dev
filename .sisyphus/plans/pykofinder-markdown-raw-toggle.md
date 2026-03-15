# Pykofinder: Markdown Raw Source View Toggle

## Status: Backlog

## Priority: 30

## TL;DR

> **Quick Summary**: Markdown files are currently always shown rendered (HTML). Add a
> rendered/raw toggle button bar — analogous to the existing JSON formatted/raw and CSV
> spreadsheet/rows toggles — so the user can inspect the raw `.md` source without leaving
> pykofinder.
>
> **Deliverables**:
>
> - `MarkdownProvider` in `providers/markdown_provider.py` — handles `.md` files,
>   two formats: `"rendered"` (default, current pipeline) and `"raw"` (plain `<pre>` source)
> - Register `MarkdownProvider` in the VFS `REGISTRY` alongside CSV and JSON providers
> - Format-toggle bar rendered in the preview column when a `.md` file is active
>   (reuses existing `.fmt-bar` / `.fmt-btn` CSS + localStorage persistence)
> - `render_preview(..., fmt="raw")` returns `<pre class="preview-raw">` with HTML-escaped source
> - `render_preview(..., fmt="rendered")` delegates to the existing markdown rendering pipeline
> - Tests in `tests/test_providers.py` (or equivalent): rendered output vs raw passthrough
>
> **Estimated Effort**: Short
> **Depends On**: —

---

## Context

### Pi-Session-File: ephemeral (acp-b671b2f0)

### Feature motivation

The JSON and CSV providers already give pykofinder a "view format" layer for structured
files. Markdown sits in a similar position — rendered output is what the user usually wants,
but when debugging wikilinks, YAML frontmatter, template syntax, or raw heading structure,
the rendered view actively hides the information they need.

The pattern already exists: `json_provider.py` with `default_fmt = "formatted"` and a
`"raw"` fallback. Markdown follows the same shape with `"rendered"` / `"raw"`.

### Current behaviour

`.md` files are rendered through `rendering.py` (markdown-it-py pipeline with wikilink,
mermaid, and relative-link transforms). There is no dedicated `VFSProvider` for markdown;
it falls through to the generic file-preview path. No toggle is shown.

### Proposed implementation sketch

```python
# providers/markdown_provider.py
class MarkdownProvider:
    def handles(self, path: Path) -> bool:
        return path.suffix.lower() == ".md"

    def default_fmt(self, vpath: str) -> str:
        return "rendered"

    def list_entries(self, path: Path, vpath: str) -> list[VFSEntry]:
        return []  # Markdown is a leaf — no sub-entries

    def render_preview(
        self, path: Path, vpath: str, fmt: str,
        page: int, limit: int, col: int = 0
    ) -> str:
        text = path.read_text(encoding="utf-8")
        if fmt == "raw":
            return f'<pre class="preview-raw">{html.escape(text)}</pre>'
        # fmt == "rendered" (default): delegate to existing pipeline
        return render_markdown(text, base_path=path.parent)
```

The format-toggle bar is automatically emitted by `list_vfs_column()` in `columns.py`
when `show_fmt_bar=True` — no new UI code needed beyond registering the provider and
wiring the two button labels (`📄 Rendered` / `📝 Raw`).

### Format bar button labels (proposed)

| Button | `data-fmt` | Icon |
|--------|------------|------|
| Rendered (default) | `rendered` | `📄` |
| Raw source | `raw` | `📝` |

### localStorage key

Format preference is persisted per file-type at `vfmt_type_.md` and per file at
`vfmt_file_<path>::`. Existing JS machinery handles this automatically.

## Non-goals

- Syntax-highlighted raw view (Pygments `.md` lexer) — nice-to-have, out of scope for v1
- Editing the raw source in-browser
- Per-section folding / outline view
