# Slack Inbound File Support (Non-Image Attachments)

## Status: Backlog

## Priority: 5

## TL;DR

> **Quick Summary**: Investigate whether the Slack agent can currently read
> non-image files attached to messages (PDFs, spreadsheets, text files, etc.).
> Image attachments are already handled (slack-inbound-images, Done). All other
> file types are currently filtered out in `extract_image_files()`. If the
> agent cannot read them, implement download-and-surface support so the agent
> can read files using the Read tool or skills like `read-as-markdown`.
>
> **Deliverables**:
>
> - Investigation: confirm current capability gap with a test file upload
> - Download non-image Slack file attachments to disk (next to image attachments)
> - Surface them in the agent prompt as `<attachment type="file" path="..." mimetype="..."/>` tags
> - Agent can then use the Read tool or `read-as-markdown` skill to process PDFs, text, etc.
> - DB column `attachment_path` already exists (added by slack-inbound-images) — reuse it or extend for multiple attachments
>
> **Estimated Effort**: Short
> **Depends On**: [slack-inbound-images](./slack-inbound-images.md)

---

## Context

### Current State

`extract_image_files()` in `handler.py` (added by the slack-inbound-images
feature) filters the `files` array on Slack message events to vision-capable
MIME types only:

```python
VISION_MIMETYPES = frozenset({"image/jpeg", "image/png", "image/gif", "image/webp"})
```

Any file with a different MIME type — PDF, DOCX, XLSX, plain text, CSV, etc.
— is silently ignored. The agent never sees it.

### Why This Matters

Teams routinely share files in Slack:

- "Here's the report PDF — can you summarize it?"
- "Check this spreadsheet, something looks off"
- "Here's the meeting notes text file"
- "Can you review this draft document?"

Currently, the agent sees the text message ("here's the report") but not the
file itself, so it cannot help.

### Technical Path

The same `url_private_download` / bot-token auth pattern used for images works
for all file types. The difference is what the agent does with the file once it
is on disk:

- **Images**: passed to `analyze_image` MCP tool (Gemini vision)
- **PDFs / text files**: agent reads them directly via the Read tool or the
  `read-as-markdown` skill
- **Spreadsheets / binary formats**: agent can use the `read-as-markdown` skill
  or report it cannot process the format

The approach: download the file, store it on disk alongside image attachments,
and surface it in the XML prompt as an `<attachment>` tag with `type="file"`,
so the agent knows the file is available and where to find it.

### Scope Boundary

- Phase 1 (this plan): download and surface all non-image file types
- The agent decides what to do with each file (Read, skill, or inform the user
  it cannot process the format)
- No automatic text extraction pipeline here — keep it simple
- Images remain handled by the vision path (no change)

---

## Work Objectives

### Core Objective

When a user attaches a PDF, text file, or other document to a Slack message,
the agent is told about it and can read its contents.

### Definition of Done

- [ ] Non-image file uploads in Slack are downloaded to
  `{data_dir}/slack_attachments/{channel_id}/{file_id}.{ext}`
- [ ] Agent prompt includes `<attachment type="file" path="..." mimetype="..." name="..."/>`
  tag for each non-image file
- [ ] Agent can use Read tool to read a plain-text or Markdown file
- [ ] Agent can use `read-as-markdown` skill to read a PDF
- [ ] Graceful failure: download errors → log warning, continue with text only
- [ ] Unit tests cover file download, XML formatting, and graceful failure

### Must Have

- Detect non-image `files` in Slack message events (any MIME type not already
  handled by vision path)
- Download via `httpx` with bot-token auth (same as image download)
- Store on disk with original extension preserved
- Surface in agent prompt as `<attachment type="file" .../>` tag
- Graceful failure on download error

### Nice to Have

- Size limit: skip files > 20 MB (log warning, inform agent)
- Track downloads in DB to avoid re-downloading on reconnect
- Multiple attachments per message (already supported structurally if XML emits
  multiple tags)

### Must NOT Have

- No automatic PDF-to-text conversion in the gateway (agent decides)
- No new MCP tools in this plan (reuse Read tool + existing skills)
- No changes to the vision / image path

---

## Investigation First

Before implementing, verify the capability gap with a manual test:

1. Upload a PDF to the Slack channel
2. Check the debug log: does the agent prompt include any `<attachment>` tag?
3. Expected result: No — the file is silently ignored

This confirms the gap and gives us a concrete test case for verification.

---

## Tasks

### 1. Extend `extract_image_files()` → `extract_attachment_files()`

**File**: `pykoclaw-slack/src/pykoclaw_slack/handler.py`

- Rename (or add alongside) `extract_image_files()` to handle all MIME types
- Split result into two lists: `image_files` (vision-capable) and
  `other_files` (everything else)
- Pass `other_files` to a new download-and-surface path

### 2. Download non-image files

**File**: `pykoclaw-slack/src/pykoclaw_slack/attachments.py`

The existing `download_slack_image()` function already has the right shape.
Add a `download_slack_file()` variant (or make the existing function
MIME-type-agnostic) that works for any file type:

```python
async def download_slack_file(
    url: str, bot_token: str, dest: Path, max_size_mb: int = 20
) -> Path | None:
    """Download any Slack file with bearer auth. Returns path or None on failure."""
    ...
```

Reuse or unify with the image download function — they are nearly identical.

### 3. Surface in XML prompt

**File**: `pykoclaw-slack/src/pykoclaw_slack/handler.py`

Update `format_xml_messages()` to emit file attachment tags:

```xml
<attachment type="file" path="/home/agent/.../slack_attachments/.../report.pdf" mimetype="application/pdf" name="Q1-report.pdf"/>
```

Use `type="image"` for images (existing behavior), `type="file"` for others.

### 4. Tests

**File**: `pykoclaw-slack/tests/test_attachments.py` (extend)

- Test: message with PDF file → `download_slack_file` called, path stored
- Test: download failure → graceful skip, text message still dispatched
- Test: `format_xml_messages` with file attachment → correct `<attachment type="file" .../>` tag
- Test: file > 20 MB → skipped with warning

---

## Verification

```bash
# Unit tests
uv run pytest pykoclaw-slack/tests/ -v -k "attachment or file"

# Manual: upload a PDF to Slack, check debug log for <attachment type="file" ...>
PYKOCLAW_LOG_LEVEL=DEBUG uv run pykoclaw slack run 2>&1 | rg "attachment"
```

---

## Related Plans

- [slack-inbound-images.md](./slack-inbound-images.md) — reference implementation (Done)
- [attachment-support.md](./attachment-support.md) — ACP attachment support (separate, not a dependency)
- [matrix-inbound-images.md](./matrix-inbound-images.md) — parallel feature for Matrix
