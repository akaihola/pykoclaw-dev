# Pykofinder: VTT Subtitle File Preview (Rendered + Raw Toggle)

## Status: Backlog

## Priority: 31

## TL;DR

> **Quick Summary**: `.vtt` (WebVTT) subtitle files currently fall through to the plain
> `<pre>` text fallback. Add a `VTTProvider` that renders a clean, readable transcript
> (timestamps and cue headers stripped, cues joined into paragraphs) as the default view,
> with a Raw toggle to inspect the original source — same pattern as the Markdown and JSON
> raw/rendered toggles.
>
> **Deliverables**:
>
> - `VTTProvider` in `providers/vtt_provider.py` — handles `.vtt` files, two formats:
>   `"transcript"` (default, clean readable text) and `"raw"` (plain `<pre>` source)
> - Register `VTTProvider` in the VFS `REGISTRY`
> - Format-toggle bar: `📜 Transcript` / `📝 Raw` — reuses existing `.fmt-bar` CSS and
>   localStorage persistence
> - `render_preview(fmt="transcript")` — parses cue blocks, strips timestamps and NOTE/STYLE
>   headers, optionally emits speaker labels if `<v Speaker>` tags are present, renders as
>   `<div class="preview-transcript">` with `<p>` per cue group
> - `render_preview(fmt="raw")` — `<pre class="preview-raw">` with HTML-escaped source
> - Tests in `tests/test_providers.py`: transcript strips timestamps, raw passthrough,
>   speaker label extraction, empty-cue and malformed-header edge cases
>
> **Estimated Effort**: Short
> **Depends On**: —

---

## Context

### Pi-Session-File: ephemeral (acp-b671b2f0)

### Why VTT?

WebVTT is the subtitle format produced by YouTube auto-captions (used by the
`youtube-to-markdown` skill), browser `<video>` tracks, and many transcription tools.
When an agent drops a `.vtt` file into the vault the raw cue syntax is noisy and hard to
read:

```
WEBVTT

00:01:23.456 --> 00:01:27.890 align:start position:0%
<c.colorE5E5E5><00:01:23.456><c> Hello,</c><00:01:24.240><c> world.</c></c>

00:01:27.890 --> 00:01:31.120 align:start position:0%
<c.colorE5E5E5><00:01:27.890><c> This</c><00:01:28.010><c> is</c></c>
```

The rendered transcript view strips all of that noise and presents plain readable text,
mirroring what the `youtube-to-markdown` skill produces as its Markdown output.

### VTT parsing sketch

```python
import re, html as html_lib
from pathlib import Path

_TIMESTAMP_LINE = re.compile(r"^\d{2}:\d{2}[:\d.]+\s*-->\s*\S+", re.MULTILINE)
_INLINE_TAG = re.compile(r"<[^>]+>")
_HEADER_KW = re.compile(r"^(?:NOTE|STYLE|REGION)\b", re.MULTILINE)


def _parse_transcript(text: str) -> list[str]:
    """Return list of cue text strings, timestamps and inline tags stripped."""
    # Drop WEBVTT header line and NOTE/STYLE/REGION blocks
    blocks = re.split(r"\n{2,}", text.strip())
    cues = []
    for block in blocks:
        lines = block.strip().splitlines()
        if not lines:
            continue
        if lines[0].startswith("WEBVTT") or _HEADER_KW.match(lines[0]):
            continue
        # Skip optional cue identifier line (no --> in it)
        start = 0
        if lines and "-->" not in lines[0]:
            start = 1
        # Skip timestamp line
        if start < len(lines) and "-->" in lines[start]:
            start += 1
        cue_text = " ".join(lines[start:]).strip()
        cue_text = _INLINE_TAG.sub("", cue_text).strip()
        if cue_text:
            cues.append(cue_text)
    return cues
```

### Speaker label handling

WebVTT supports `<v Speaker Name>cue text</v>` voice spans. If detected, emit cues as:

```html
<p><strong>Speaker Name:</strong> Cue text here.</p>
```

If no voice spans are present, emit cues as plain `<p>` elements, merging short consecutive
cues (< 80 chars) into the same paragraph to reduce visual fragmentation.

### CSS for transcript view

Add a minimal `.preview-transcript` rule to `styles.py`:

```css
.preview-transcript {
    padding: 12px 16px;
    line-height: 1.6;
    font-size: 14px;
    overflow-y: auto;
}
.preview-transcript p {
    margin: 0 0 0.5em;
}
```

### Format bar button labels

| Button | `data-fmt` | Icon |
|--------|------------|------|
| Transcript (default) | `transcript` | `📜` |
| Raw source | `raw` | `📝` |

### localStorage key

`vfmt_type_.vtt` (type-level) and `vfmt_file_<path>::` (file-level). Existing JS handles
this automatically.

## Non-goals

- Audio playback or `<video>` embedding
- Timestamp-linked navigation (click timestamp → seek)
- `.srt` / `.ass` / `.ssa` format support (separate issue if needed)
- Editing cues in-browser
