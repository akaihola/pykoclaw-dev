# Pykofinder: WikilinkIndex Refresh on Cache Miss

## Status: Backlog

## Priority: 8

## TL;DR

When `WikilinkIndex.resolve()` returns `None`, rebuild the index from the
filesystem and retry once before giving up. This catches files created after
the index was built (e.g. by a scheduled task in the same session that produced
the reply being transformed).

Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-26T14-42-53-546Z_41f909ec-ca5e-40d6-8941-f06262fd110c.jsonl

## Problem

The `WikilinkIndex` is built once on the first `transform_response()` call and
cached for the lifetime of the channel plugin process (Matrix, Slack, etc.).
Files created after the index is built are invisible to wikilink resolution.

**Observed failure (2026-03-24):** Tyko's weekly Agent Commons task created
`pages/Projects/Agent Commons/Response scenarios - BSAG and JNF.md` at 07:06
UTC, then referenced it as `[[Agent Commons/Response scenarios - BSAG and JNF]]`
in the final reply at 07:08 UTC. The Matrix Tyko service had been running since
well before March 24 — its cached index didn't include the new file, so
`index.resolve()` returned `None` and the wikilink was delivered as raw
`[[...]]` text.

The original pykofinder plan noted this as a known limitation:

> No file-watcher / live index refresh (index built once at plugin init)

## Design

**Refresh-on-miss strategy in `PykofinderPlugin.transform_response()`:**

1. Run `transform_links()` with the cached index (fast path — no change for the
   common case where all files predate the index).
2. If the result still contains unresolved `[[...]]` wikilinks, rebuild the
   index from the filesystem and run `transform_links()` again.
3. Any wikilinks still unresolved after the second pass are genuinely missing —
   log the warning as today.

The rebuild is triggered at most once per `transform_response()` call, so the
worst case is two filesystem scans per delivery with unresolved links. In
practice most deliveries resolve everything on the first pass and never rebuild.

**Alternative considered — rebuild inside `_replace_wikilink()`:** This would
rebuild the index mid-regex-substitution. Simpler logic but the index might
get rebuilt N times if there are N unresolved wikilinks in one message. The
two-pass approach is cleaner.

## Implementation

### Files to change

- `pykoclaw-pykofinder/src/pykoclaw_pykofinder/__init__.py` —
  `PykofinderPlugin.transform_response()`: after `transform_links()`, check if
  `WIKILINK_RE` still matches in the result. If so, rebuild `self._index` and
  call `transform_links()` again.

- `pykoclaw-pykofinder/tests/test_transform.py` — add a test:
  1. Build an index from a tmpdir with file A.
  2. Transform a wikilink to file B (not yet created) — confirm it's unchanged.
  3. Create file B on disk.
  4. Call `transform_response()` again — confirm the wikilink is now resolved
     (the refresh-on-miss rebuilt the index).

### Effort

Quick (< 1 hour). The logic change is ~10 lines in `transform_response()` plus
a test.
