# Pykofinder: Handle HTML `<img>` Tags in Transform

## Status: Done

## Completed: 2026-03-08

## TL;DR

> **Quick Summary**: `transform.py` in `pykoclaw-pykofinder` only rewrites
> markdown image syntax (`![alt](path)`) and wikilinks. When the pykoclaw
> agent generates HTML `<img src="path" alt="..."/>` tags instead, they pass
> through the transform unchanged. Mitto's post-render file-link converter
> then inserts an `<a href="mitto/api/files?...">` anchor into the `src`
> attribute, producing garbled HTML that renders as broken text in the chat.
>
> **Fix**: Add an `HTML_IMG_RE` pattern to `transform.py` that matches
> `<img src="..." alt="..."/>` tags with local file paths and rewrites them
> to `![alt](pykofinder_url)` (or the native-extension variant) before the
> response reaches Mitto.
>
> **Deliverables**:
>
> - `HTML_IMG_RE` + `_ALT_RE` + `_SRC_RE` compiled regexes in `transform.py`
> - `_replace_html_img()` handler function
> - `HTML_IMG_RE.sub(...)` pass inserted in `transform_links()` before the
>   markdown-image pass
> - Regression tests in `test_transform.py`
>
> **Estimated Effort**: XS (< 1 hour)
> **Depends On**: `pykoclaw-pykofinder` plugin (already done)

---

## Context

### Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-pykoclaw--/2026-03-08T10-47-47-979Z_4063f1b3-503b-4357-89af-f7c123d22306.jsonl

### How the bug was found

1. User asked the pykoclaw agent (ACP session `12c965ce`, Claude Code session
   `2371dd05`) to show 5 vault images. Agent first replied with text
   descriptions; user followed up with "Could you give them as markdown
   `![]()` images?"

2. Agent replied with a numbered list. Items 1–3 (filenames contain spaces,
   e.g. `2024-09-15 wheeloflife dot io.png`) were emitted as markdown
   `![alt](/abs/path with spaces)`. Items 4–5 (no spaces in filename,
   `viz-act1.png`, `viz-full.png`) were emitted as HTML
   `<img src="/home/agent/my-knowledge/viz-act1.png" alt="Viz Act 1 - The Interleave"/>`.

3. The pykofinder `transform_response` hook ran **but silently skipped HTML
   img tags** — the three regexes (`WIKILINK_RE`, `MARKDOWN_IMAGE_RE`,
   `MARKDOWN_LINK_RE`) all require markdown syntax, so items 4–5 passed
   through untouched.

4. Mitto received the raw HTML `<img src="/home/agent/.../viz-act1.png"
alt="..."/>`, rendered it through its markdown pipeline (HTML is allowed in
   Mitto's markdown renderer), then its **file-link post-processor** matched
   the local path inside the `src="..."` attribute and replaced it with
   `<a href="mitto/api/files?ws=...&path=%2F..." class="file-link">`.

5. The result was a mangled `<img>` tag with the Mitto anchor injected into
   its `src` attribute — rendered by the browser as:

   ```
   /home/agent/my-knowledge/viz-act1.png" alt="Viz Act 1 - The Interleave"/>
   ```

   (the `<img src="<a href="...` and closing `</a>` were swallowed by HTML
   attribute parsing, leaving only the link text and the trailing markup).

### Why items 1–3 were unaffected by the file-link corruption

Items 1–3 have spaces in their file paths. Mitto's file-link post-processor
uses a regex that requires no whitespace in paths, so it did not match. The
markdown `![alt](path with spaces)` strings were also not parsed as images by
the markdown renderer (spaces in bare URLs are invalid in CommonMark), so they
were emitted as literal text inside `<p>` elements — ugly, but not corrupted.

(If `PYKOCLAW_PYKOFINDER_BASE_URL` were configured, items 1–3 would have been
converted to pykofinder URLs with percent-encoded spaces before hitting Mitto,
and would render as proper images. Items 4–5 would also render correctly once
the HTML img fix is in place.)

### Verified source of the bug

- **`transform.py`** has no handling for HTML `<img>` tags.
  All three regexes (`WIKILINK_RE`, `MARKDOWN_IMAGE_RE`, `MARKDOWN_LINK_RE`)
  are markdown-only.
- **`__init__.py`** correctly skips the transform when `base_url` is `None`,
  but the HTML img bug manifests even when `base_url` IS configured, because
  the tag simply isn't matched.
- **The Mitto file-link post-processor** runs after markdown rendering and
  replaces bare local file paths with Mitto API links — this is correct
  behaviour for text, but destructive when the path appears inside an HTML
  attribute.

### Exact Mitto-rendered HTML (from user-provided source)

```html
<li>
  <p>
    <img
      src="&lt;a href="
      mitto=""
      api=""
      files?ws='a1b2c3d4-5678-4abc-9def-222222222222&amp;path=%2Fhome%2Fagent%2Fmy-knowledge%2Fviz-act1.png"'
      class="file-link"
    />/home/agent/my-knowledge/viz-act1.png" alt="Viz Act 1 - The
    Interleave"/&gt;
  </p>
</li>
```

---

## Fix

### `transform.py` changes

Add three new regexes at module level:

```python
HTML_IMG_RE = re.compile(
    r'<img\b([^>]*?)/?>', re.IGNORECASE
)
_SRC_ATTR_RE = re.compile(r'\bsrc="([^"]*)"', re.IGNORECASE)
_ALT_ATTR_RE = re.compile(r'\balt="([^"]*)"', re.IGNORECASE)
```

Add a new handler:

```python
def _replace_html_img(
    match: re.Match[str],
    base_url: str,
    workspace_root: Path,
    *,
    ctx: TransformContext,
) -> str:
    attrs = match.group(1)
    src_m = _SRC_ATTR_RE.search(attrs)
    if src_m is None:
        return match.group(0)           # no src — leave untouched

    src = src_m.group(1).strip()
    if _has_scheme(src):
        return match.group(0)           # already an HTTP/data/… URL

    alt_m = _ALT_ATTR_RE.search(attrs)
    alt = alt_m.group(1) if alt_m else ""

    abs_path = Path(src) if src.startswith("/") else workspace_root / src
    if abs_path.suffix.lower() not in _IMAGE_SUFFIXES:
        return match.group(0)           # not an image type we handle

    if ctx.supports_extension(abs_path.suffix):
        return f"![{alt}]({abs_path})"

    url = make_pykofinder_url(base_url, abs_path)
    return f"![{alt}]({url})"
```

In `transform_links()`, add the HTML img pass **before** the markdown-image
pass so that any HTML img tags are normalised to markdown first, avoiding any
risk of double-processing:

```python
def transform_links(text, base_url, workspace_root, index, ctx=None):
    ctx = ctx or TransformContext(
        channel_prefix="default", native_file_extensions=frozenset()
    )
    text = WIKILINK_RE.sub(
        lambda m: _replace_wikilink(m, base_url, index, ctx), text
    )
    # NEW: normalise HTML <img> to markdown ![alt](url) first
    text = HTML_IMG_RE.sub(
        lambda m: _replace_html_img(m, base_url, workspace_root, ctx=ctx), text
    )
    text = MARKDOWN_IMAGE_RE.sub(
        lambda m: _replace_markdown_link(
            m, base_url, workspace_root, is_image=True, ctx=ctx
        ),
        text,
    )
    return MARKDOWN_LINK_RE.sub(
        lambda m: _replace_markdown_link(
            m, base_url, workspace_root, is_image=False, ctx=ctx
        ),
        text,
    )
```

### Tests to add in `test_transform.py`

```python
def test_html_img_tag_rewritten_to_pykofinder_url(tmp_path):
    index = WikilinkIndex(tmp_path)
    text = '<img src="/home/agent/my-knowledge/viz-act1.png" alt="Viz Act 1"/>'
    result = transform_links(text, "http://example.test/w/", tmp_path, index)
    expected_url = make_pykofinder_url(
        "http://example.test/w/",
        Path("/home/agent/my-knowledge/viz-act1.png"),
    )
    assert result == f"![Viz Act 1]({expected_url})"


def test_html_img_tag_native_extension_keeps_local_path(tmp_path):
    index = WikilinkIndex(tmp_path)
    text = '<img src="/home/agent/my-knowledge/viz-full.png" alt="Viz Full"/>'
    ctx = TransformContext(channel_prefix="wa", native_file_extensions=frozenset({".png"}))
    result = transform_links(text, "http://example.test/w/", tmp_path, index, ctx)
    assert result == "![Viz Full](/home/agent/my-knowledge/viz-full.png)"


def test_html_img_self_closing_variant(tmp_path):
    index = WikilinkIndex(tmp_path)
    text = '<img src="/home/agent/my-knowledge/pic.jpg" alt="Label" />'
    result = transform_links(text, "http://example.test/w/", tmp_path, index)
    expected_url = make_pykofinder_url(
        "http://example.test/w/", Path("/home/agent/my-knowledge/pic.jpg")
    )
    assert result == f"![Label]({expected_url})"


def test_html_img_http_src_left_untouched(tmp_path):
    index = WikilinkIndex(tmp_path)
    text = '<img src="https://example.com/remote.png" alt="Remote"/>'
    result = transform_links(text, "http://example.test/w/", tmp_path, index)
    assert result == text


def test_html_img_alt_order_agnostic(tmp_path):
    """alt before src should still work."""
    index = WikilinkIndex(tmp_path)
    text = '<img alt="My Image" src="/home/agent/my-knowledge/pic.png"/>'
    result = transform_links(text, "http://example.test/w/", tmp_path, index)
    expected_url = make_pykofinder_url(
        "http://example.test/w/", Path("/home/agent/my-knowledge/pic.png")
    )
    assert result == f"![My Image]({expected_url})"
```

---

## Non-goals

- Handling `<img srcset="...">` (multi-resolution) — not generated by Claude
- Handling `<picture>` / `<source>` elements
- Fixing Mitto's file-link post-processor directly (outside pykoclaw scope)
- Suppressing Claude's HTML img output via system-prompt engineering (fragile;
  the transform fix is more robust)
