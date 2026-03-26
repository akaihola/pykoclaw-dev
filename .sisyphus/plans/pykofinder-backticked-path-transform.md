# Pykofinder: Transform Bare Backticked Workspace Paths

## Status: Backlog

## Priority: 9

## TL;DR

Detect backtick code spans like `` `pages/Projects/Report.html` `` that match
an existing file in the workspace and convert them to pykofinder links. This is
a robustness fallback for when the agent uses backticks instead of the
instructed `[label](path)` markdown link syntax.

Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-26T14-42-53-546Z_41f909ec-ca5e-40d6-8941-f06262fd110c.jsonl

## Problem

The system prompt instructs the agent to use markdown link syntax for paths
containing slashes, but agents sometimes use backtick code spans instead:

```
`pages/Projects/Agent Commons report.html` now reflects Week 4
```

The pykofinder transform handles wikilinks, markdown links,
backticked-markdown-links (`\`[label](path)\``), and HTML `<img>` tags — but
has no handler for **bare backticked paths**. These pass through unchanged,
appearing as monospace text in the delivered message instead of clickable links.

**Observed failure (2026-03-24):** Tyko's Agent Commons weekly report referred
to `` `pages/Projects/Agent Commons report.html` `` in backticks. The file
exists in the workspace but was not converted to a pykofinder link.

## Design

Add a new regex pass in `transform_links()` that matches backtick code spans
containing a `/` (indicating a path-like string). For each match:

1. Strip the backticks to get the raw path string.
2. Resolve it relative to `workspace_root`.
3. If the absolute path exists on disk, replace the backtick span with a
   pykofinder link: `[filename](viewer-url)` for non-images,
   `![filename](static-url)` for image suffixes.
4. If the path doesn't exist, leave the backtick span unchanged.

**Regex:** `` `([^`\n]+/[^`\n]+)` `` — matches a backtick span containing at
least one slash. The slash requirement avoids false positives on inline code
like `` `variable_name` `` or `` `command --flag` ``.

**Ordering in `transform_links()`:** Run this pass AFTER wikilink and markdown
link passes, so it only catches paths that weren't already handled by proper
link syntax. Run BEFORE the backticked-markdown-link restore step.

### Edge cases

- Absolute paths (`` `/home/agent/...` ``): resolve directly; the system prompt
  forbids these but agents emit them. Convert if the file exists.
- Home-relative paths (`` `~/...` ``): expand with `Path.expanduser()`.
- Paths with `#fragment`: split on first `#`, resolve path part only.
- Already-protected backticked markdown links: handled earlier in the pipeline,
  won't be matched.
- Multiple backtick spans on one line: the regex handles this (non-greedy match
  between backtick pairs).

## Implementation

### Files to change

- `pykoclaw-pykofinder/src/pykoclaw_pykofinder/transform.py`:
  - Add `BACKTICKED_PATH_RE` regex.
  - Add `_replace_backticked_path()` replacement function.
  - Insert the pass in `transform_links()` after the markdown link pass.

- `pykoclaw-pykofinder/tests/test_transform.py`:
  - Backticked relative path matching existing file → converted to link.
  - Backticked relative path not matching any file → left as backtick span.
  - Backticked string without slash → left unchanged (not a path).
  - Backticked absolute path matching existing file → converted.
  - Image suffix → `![](url)` instead of `[](url)`.
  - Path with `#heading` fragment → fragment preserved in URL.

### Effort

Quick (< 1 hour). One regex + replacement function + tests.
