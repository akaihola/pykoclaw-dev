# Pykofinder Link Translation Plugin

## Status: Done

## Completed: 2026-03-08

## Priority: 10

## TL;DR

> **Quick Summary**: Add a `pykoclaw-pykofinder` plugin that post-processes LLM
> responses and rewrites internal document/file links (Markdown links and
> Obsidian-style wikilinks) to point to files served by a running pykofinder
> instance, while preserving local media paths for channels that explicitly
> declare native attachment support. The transformation happens after the agent
> replies but before channel-specific formatting, and is parameterised by the
> target channel's native file capabilities.
>
> **Deliverables**:
>
> - `pykoclaw-pykofinder/` — new uv workspace member + package
> - context-aware `transform_response` hook in core + dispatch pipeline
> - Link transformation engine: relative links, absolute links, wikilinks
> - Channel-native file capability declarations
> - Obsidian-compatible wikilink index with full wikilink syntax support
> - Native media path preservation in `pykoclaw-whatsapp` and `pykoclaw-matrix`
> - Comprehensive test suite
>
> **Estimated Effort**: Medium
> **Depends On**: —

---

## Context

### Current state

When the agent references a file in its reply — e.g. `[see this page](pages/Introduction.md)`
or a wikilink `[[Front Page]]` — the raw path or wiki-syntax leaks through to
the user as unclickable text. Channel formatters (WhatsApp, Matrix) have no way
to turn these into actionable links.

### What pykofinder is

Pykofinder is a locally-running HTTP file browser that serves a directory tree.
A typical deployment serves the agent's knowledge base (e.g. `~/my-knowledge/`)
at an address like `http://gogo.crane-boa.ts.net:8334/`. Its viewer endpoint
accepts a `?path=` query parameter with an absolute filesystem path:

```
http://gogo.crane-boa.ts.net:8334/w/?path=/home/agent/my-knowledge/pages/Introduction.md
```

### Workspace root = `PYKOCLAW_DATA`

The pykoclaw data directory (`settings.data`, set via `PYKOCLAW_DATA`) doubles as
the knowledge-base workspace root. In practice each agent instance has its own
`PYKOCLAW_DATA` pointing at its knowledge directory (e.g. `/home/agent/ressu-knowledge`).
The pykofinder plugin derives the workspace root from `pykoclaw.config.settings.data`
— no separate config needed for the path.

### Current media handling

Both `pykoclaw-whatsapp` and `pykoclaw-matrix` split agent responses into
interleaved text and media segments (`split_segments()`). They already recognise
**absolute local file paths** as native attachments and can read/upload those
from disk. ACP/Mitto, by contrast, renders text/Markdown and cannot natively
open arbitrary local paths from the agent host.

This means the pykofinder transform should not treat every channel the same:
channels with declared native support for a media file type should keep local
absolute paths for those files, while channels without native support should
receive pykofinder HTTP URLs instead.

---

## Architecture

### Package layout

```
pykoclaw-pykofinder/
├── pyproject.toml
└── src/pykoclaw_pykofinder/
    ├── __init__.py          # PykofinderPlugin class
    ├── config.py            # PykofinderSettings (PYKOCLAW_PYKOFINDER_BASE_URL)
    ├── transform.py         # link rewriting entry point
    └── index.py             # WikilinkIndex — filesystem scan + resolution
```

The package is added as a uv workspace member in the root `pyproject.toml`.

### Plugin hook: `transform_response`

A new method is added to the plugin protocol, with channel context:

```
PykoClawPlugin.transform_response(text: str, ctx: TransformContext) -> str
```

`TransformContext` carries the target channel prefix plus the set of file
extensions the channel can handle natively from disk.

`PykoClawPluginBase` provides an identity default. `dispatch_to_agent()` in
`pykoclaw-messaging` continues to accept an optional response transformer, but
channel plugins now build that transformer for a specific `TransformContext`.
After assembling `full_text` from the agent stream but before returning
`DispatchResult`, it applies the transformer:

```
full_text = response_transformer(full_text)   # if transformer is not None
```

Channel plugins build the composite transformer by loading all plugins,
constructing the channel's `TransformContext`, and chaining each plugin's
`transform_response` for that context.

### How channel plugins pass the transformer

Each channel plugin's CLI `run` command currently calls `run_db_migrations` with
just its own plugin. It should instead call `load_plugins()` to get ALL loaded
plugins, run DB migrations for all of them, declare the channel's native file
capabilities, and build a composite transformer for that channel:

```
all_plugins = load_plugins()
run_db_migrations(db, all_plugins)
ctx = TransformContext(
    channel_prefix="wa",
    native_file_extensions=WhatsAppPlugin.native_file_extensions(),
)
transformer = compose_transformers(all_plugins, ctx)
```

`compose_transformers` is a small helper (can live in `pykoclaw.plugins`) that
returns a single `Callable[[str], str]` that applies each plugin's
`transform_response` in registration order for the provided context.

`WhatsAppConnection.__init__` and `MatrixConnection.__init__` gain a
`response_transformer: Callable[[str], str] | None = None` parameter, stored as
`self._response_transformer` and passed through to every `dispatch_to_agent` call.

### Config

`PykofinderSettings` (prefix `PYKOCLAW_PYKOFINDER_`) has one field:

- `base_url: str | None = None` — the pykofinder viewer endpoint, e.g.
  `http://gogo.crane-boa.ts.net:8334/w/`

When `base_url` is `None`, `transform_response` is a no-op (pykofinder not
configured). This means the plugin can be installed without being active.

### URL construction

Given:

- `base_url` = `http://host:port/w/`
- `workspace_root` = `settings.data` (a `Path`)
- A local absolute path `p`

The pykofinder URL is: `base_url + "?path=" + percent_encode(str(p))`

where `percent_encode` applies `urllib.parse.quote(s, safe="")` — all characters
including slashes and spaces are encoded (pykofinder reads the `path=` query
parameter as a single value, not a path segment).

For a relative path `rel`, the absolute path is `workspace_root / rel`.

### Link types handled

The transformer processes the full raw text returned by the agent (the entire
`full_text`, including any `<reply>` tags — those are extracted later by channel
plugins). Processing order:

1. **Obsidian wikilinks** — `[[...]]` patterns (see below)
2. **Markdown image links** — `![alt](path-or-relative-url)`
3. **Markdown text links** — `[text](path-or-relative-url)`

Rules for items 2 and 3:

- If the URL already starts with a recognised scheme (`http://`, `https://`,
  `ftp://`, `mailto:`, etc.) → **leave untouched**
- Text/document links are always rewritten to pykofinder URLs
- Media/image links are conditional:
  - if the resolved target extension is in `ctx.native_file_extensions` → keep
    it as an absolute local path so the channel can deliver it natively
  - otherwise → construct a pykofinder URL
- Relative local paths are resolved against `workspace_root` before either
  preserving them or converting them to URLs

### Wikilink index and Obsidian resolution semantics

`WikilinkIndex` scans `workspace_root` recursively at plugin initialisation time
(once, no file-watcher in v1) and builds:

- A mapping from lowercased filename stem → list of `Path` objects (relative to
  workspace root), sorted by ascending path depth (fewest components first), then
  alphabetically.

**Full Obsidian wikilink syntax supported:**

| Syntax                            | Meaning                                                     |
| --------------------------------- | ----------------------------------------------------------- |
| `[[Note]]`                        | Find `Note.md` (or any extension if no `.md` match)         |
| `[[Note\|alias]]`                 | Same, render as `[alias](url)`                              |
| `[[Note#Heading]]`                | Same, append `#Heading` as URL fragment                     |
| `[[Note#Heading\|alias]]`         | Same with alias display text                                |
| `[[path/to/Note]]`                | Path-qualified: match only at that subpath within workspace |
| `[[path/to/Note#Heading]]`        | Path-qualified with heading                                 |
| `[[path/to/Note\|alias]]`         | Path-qualified with alias                                   |
| `[[path/to/Note#Heading\|alias]]` | All three combined                                          |

**Resolution algorithm** (for the stem/name part, without heading):

1. Normalise the name: strip any heading fragment (`#...`) and alias (`|...`),
   trim whitespace.
2. If the name contains `/` (path-qualified): look for a file whose path from
   workspace root ends with the given subpath (case-insensitive). Return the
   first (shortest) match.
3. Otherwise: look up the lowercased stem in the index. Among all matches,
   prefer `.md` extension. Return the entry with the fewest path components
   (shortest relative path). Break ties alphabetically.
4. If no match: return `None`. Log a `WARNING` and leave the wikilink unchanged
   in the output text.

**Extension preference**: when no extension is given in the wikilink, prefer
`.md`. If no `.md` file matches but another extension does, use that.

**Heading fragment**: if a `#Heading` was present, append it to the constructed
URL as `#` + `urllib.parse.quote(heading, safe="")` (the fragment is
URL-encoded but kept as a fragment, not part of the `?path=` value).

**Embedded wikilinks** (`![[Note.png]]`): treated like a markdown image — after
resolving the path, emit `![Note.png](pykofinder_url)`. Note embeds
(`![[Note.md]]`) emit a plain text link `[Note.md](pykofinder_url)`.

---

## Native media capabilities in channel plugins

The pykofinder transform should preserve native local media paths for channels
that declare support for them, and only fall back to HTTP URLs for channels
without native support (notably ACP/Mitto).

### Changes to `pykoclaw-whatsapp`

**`__init__.py` or plugin class**: declare native file extensions that WhatsApp
can send from disk (at minimum the already-supported image extensions; optionally
video/document types as follow-up work).

**`segments.py`**: keep absolute local-path media detection as the primary native
attachment mechanism. Avoid new URL-only branches unless required for ACP/Mitto-
style transformed responses.

**`connection.py`**: continue sending native attachments from disk for preserved
local paths. Any temporary URL-download support should be removed or minimised if
capability-aware transforms make it unnecessary.

### Changes to `pykoclaw-matrix`

**`__init__.py` or plugin class**: declare native file extensions that Matrix
can send from disk.

**`segments.py`**: keep native local-path media detection as the primary
attachment mechanism alongside Mermaid handling.

**`connection.py`**: continue uploading native attachments from disk for
preserved local paths. As with WhatsApp, URL-download support should be avoided
unless still needed for backward compatibility.

### ACP / Mitto

ACP/Mitto declares no native local-file capability. For ACP-targeted responses,
media links should still be rewritten to pykofinder HTTP URLs so Mitto can render
or link to them in chat.

---

## Tasks

### Task 1 — Plugin protocol: `transform_response` hook

**Files**: `pykoclaw/src/pykoclaw/plugins.py`, `pykoclaw-messaging/src/pykoclaw_messaging/dispatch.py`

- Add `transform_response(self, text: str) -> str` to `PykoClawPlugin` protocol
  (returns `text` unchanged by default in `PykoClawPluginBase`).
- Add `compose_transformers(plugins: list[PykoClawPlugin]) -> Callable[[str], str]`
  helper in `plugins.py` — chains each plugin's `transform_response` and returns
  a single callable. If all are no-ops, may return identity directly.
- Add `response_transformer: Callable[[str], str] | None = None` parameter to
  `dispatch_to_agent()`.
- After assembling `full_text` in `_run_agent()` (or after `dispatch_to_agent`
  assembles its final result), apply the transformer if provided.

### Task 2 — `pykoclaw-pykofinder` package skeleton

**New package**: `pykoclaw-pykofinder/`

- `pyproject.toml` with `pykoclaw >= 0.1` dependency and entry point
  `pykofinder = "pykoclaw_pykofinder:PykofinderPlugin"` under
  `[project.entry-points."pykoclaw.plugins"]`.
- `config.py`: `PykofinderSettings(BaseSettings)` with `env_prefix = "PYKOCLAW_PYKOFINDER_"`,
  `env_file` pointing to the same locations as core settings, and field
  `base_url: str | None = None`. Provide `get_config()` factory cached with
  `functools.lru_cache`.
- `__init__.py`: `PykofinderPlugin(PykoClawPluginBase)` that:
  - Overrides `transform_response(self, text: str) -> str` — if `base_url` is
    `None`, returns `text` unchanged; otherwise calls the transform engine.
  - Overrides `get_config_class()` returning `PykofinderSettings`.
  - Builds the `WikilinkIndex` lazily on first `transform_response` call, using
    `pykoclaw.config.settings.data` as the workspace root.
- Add `pykoclaw-pykofinder` to the workspace members list in the root
  `pyproject.toml`.

### Task 3 — Link transformation engine

**File**: `pykoclaw-pykofinder/src/pykoclaw_pykofinder/transform.py`

Public entry point:
`transform_links(text: str, base_url: str, workspace_root: Path, index: WikilinkIndex) -> str`

Process the text in a single pass where possible, or in three explicit passes
(wikilinks first, then image links, then text links). Using `re.sub` with a
callable replacement is the recommended approach for each pattern.

**Wikilink regex**: Match `!?\[\[` then capture everything up to `\]\]`. Parse
the captured group to extract: optional path-qualified stem, optional `#heading`,
optional `|alias`, and whether it starts with `!` (embed). The regex must handle
nested square brackets conservatively (wikilink syntax does not nest brackets).

**Markdown image regex**: Match `!\[([^\]]*)\]\(([^)]+)\)` — do NOT rewrite if
the URL group starts with a known scheme.

**Markdown link regex**: Match `\[([^\]]*)\]\(([^)]+)\)` — same scheme check.
Be careful not to double-rewrite image links; process images first OR use a
single unified regex that distinguishes by the leading `!`.

**URL construction helper**: `make_pykofinder_url(base_url: str, abs_path: Path, fragment: str | None) -> str`
— percent-encode the stringified path with `urllib.parse.quote(safe="")`, append
`?path=` to `base_url`, optionally append `#fragment`.

**Scheme detection**: check against a set of recognised prefixes (`http://`,
`https://`, `ftp://`, `mailto:`, `file://`, `#`, `data:`) — leave those
untouched.

### Task 4 — Wikilink index

**File**: `pykoclaw-pykofinder/src/pykoclaw_pykofinder/index.py`

`class WikilinkIndex:`

- `__init__(self, workspace_root: Path)` — immediately calls `_build()`.
- `_build(self)` — walks `workspace_root` with `Path.rglob("*")`, skipping
  hidden directories (components starting with `.`). For each file, records
  its `Path` relative to workspace root. Stores in `dict[str, list[Path]]`
  keyed by lowercased stem (filename without extension). Each list is sorted
  by `(len(p.parts), str(p))` — fewest path components first, then alpha.
- `resolve(self, name: str, path_hint: str | None = None) -> Path | None` —
  implements the resolution algorithm described in the architecture section.
  Returns the absolute path (`workspace_root / relative`), or `None` if not
  found.
- `workspace_root: Path` property — exposed so callers can construct URLs.

### Task 5 — Wire up in channel plugins

**Files**: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py`,
`pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`,
`pykoclaw-matrix/src/pykoclaw_matrix/__init__.py`,
`pykoclaw-matrix/src/pykoclaw_matrix/connection.py`

**In each `run` command** (inside the plugin's `register_commands`):

- Replace `run_db_migrations(db, [plugin])` with `run_db_migrations(db, all_plugins)`
  where `all_plugins = load_plugins()`.
- Build `transformer = compose_transformers(all_plugins)`.
- Pass `response_transformer=transformer` to the `Connection` constructor.

**`WhatsAppConnection.__init__`**: add `response_transformer: Callable[[str], str] | None = None`,
store as `self._response_transformer`. Pass to every `dispatch_to_agent()` call
in the file. There are currently two call sites.

**`MatrixConnection.__init__`**: same change; two call sites.

### Task 6 — URL image segments: WhatsApp

**Files**: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/images.py`,
`pykoclaw-whatsapp/src/pykoclaw_whatsapp/segments.py`,
`pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`

**`images.py`**: add `IMAGE_URL_MD_RE` — a compiled pattern matching
`!\[([^\]]*)\]\((https?://[^)]+)\)`, capturing `(alt_text, url)`.

**`segments.py`**:

- Extend `ImageRef.kind` to `Literal["file", "url"]`.
- In `split_segments()`, add a scan using `IMAGE_URL_MD_RE`. Markers from URL
  pattern are added alongside file-path markers, then sorted by position.

**`connection.py`**: in `_send_message()`, add an `elif ref.kind == "url":` branch:

- Download via `urllib.request.urlopen` (sync; no new dependency needed) with a
  reasonable timeout (10 s).
- Guess MIME type from the URL path's suffix using `mimetypes.guess_type`.
- Build a temporary `Path`-like name for logging from the URL's last path segment.
- Call `_send_image(jid, ...)` — but `_send_image` currently takes a `Path`.
  Either add a bytes-based overload, or factor out `_send_image_bytes(jid, data, caption)`.
- Log on download failure (do not raise — degrade gracefully to skipping the image).

### Task 7 — URL image segments: Matrix

**Files**: `pykoclaw-matrix/src/pykoclaw_matrix/images.py`,
`pykoclaw-matrix/src/pykoclaw_matrix/segments.py`,
`pykoclaw-matrix/src/pykoclaw_matrix/connection.py`

Same structure as Task 6 but async:

**`images.py`**: add `IMAGE_URL_MD_RE` (same pattern).

**`segments.py`**: extend `ImageRef.kind` to `Literal["mermaid", "file", "url"]`.
Add URL image scan alongside existing mermaid and file scans. Sort all markers
by position; filter overlapping (same logic already present).

**`connection.py`**: in `_send_message()`, add `elif ref.kind == "url":` branch
using `httpx.AsyncClient` (already imported for cross-signing code) or add
`httpx` if not already a dependency. Download bytes, guess MIME type, derive
filename from URL, call `_send_image(room_id, data, filename, mime)`.

### Task 8 — Tests

**`pykoclaw-pykofinder/tests/test_transform.py`** — parametrised pytest cases (no
filesystem needed except for wikilink resolution tests which use `tmp_path`):

- Relative Markdown link → pykofinder URL with correct percent-encoding
- Absolute Markdown link → pykofinder URL preserving the absolute path
- Already-HTTP link → untouched
- Relative Markdown image link → pykofinder URL
- Absolute Markdown image link → pykofinder URL
- `[[Note]]` → resolved URL (requires `tmp_path` with a `Note.md`)
- `[[Note|alias]]` → `[alias](url)`
- `[[Note#Heading]]` → URL with `#Heading` fragment
- `[[Note#Heading|alias]]` → combined
- `[[path/to/Note]]` → path-qualified resolution
- Unresolved wikilink → unchanged, no exception
- Mixed content (prose + wikilinks + plain links) → all transformed correctly
- Spaces in path → `%20` encoding
- Slashes in path → encoded in `?path=` value
- No `base_url` configured → text returned unchanged

**`pykoclaw-pykofinder/tests/test_index.py`**:

- Single file in workspace → resolved correctly
- Multiple files with same stem → shortest path wins
- Path-qualified name → correct file selected even with same-stem ambiguity
- Case-insensitive match → `[[front page]]` finds `Front Page.md`
- No match → `None` returned
- Hidden directories (`.obsidian/`, `.git/`) → their contents excluded from index
- Extension preference → `note.md` preferred over `note.canvas`
- `[[Note.md]]` with explicit extension → works
- Heading fragment stripped for file lookup, preserved for URL fragment

**`pykoclaw-whatsapp/tests/test_segments.py`** (extend existing):

- `![alt](https://example.com/image.png)` in text → produces `ImageSegment`
  with `ref.kind == "url"` and correct URL
- Mixed local path + URL image in same text → correct order preserved
- Plain HTTP link (not image, i.e. `[text](http://...)`) → NOT treated as image

**`pykoclaw-matrix/tests/test_segments.py`** (extend existing, or create if missing):

- Same cases as WhatsApp
- Mermaid block + URL image in same text → both detected, order preserved

---

## Implementation Checklist

### Root workspace — `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder`

- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pyproject.toml` — add `pykoclaw-pykofinder` as a uv workspace member
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/TASKS.md` — track the implementation slices for this feature
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/.sisyphus/plans/pykoclaw-pykofinder.md` — keep the checklist/status current as slices land
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/.sisyphus/BACKLOG.md` — regenerate via `bin/update-backlog.sh` after plan edits

### Core repo — `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw`

- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw/src/pykoclaw/plugins.py` — add `transform_response()` to the plugin protocol/base class and add `compose_transformers()`
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw/tests/test_plugins.py` — cover default transform behaviour and transformer chaining order

### Messaging repo — `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-messaging`

- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-messaging/src/pykoclaw_messaging/dispatch.py` — accept `response_transformer` and apply it to final `full_text`
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-messaging/tests/test_dispatch.py` — verify transformed output and callback semantics stay correct

### New plugin repo — `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder`

- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder/pyproject.toml` — create package metadata, workspace source, and plugin entry point
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder/src/pykoclaw_pykofinder/config.py` — add cached settings loader for `PYKOCLAW_PYKOFINDER_BASE_URL`
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder/src/pykoclaw_pykofinder/index.py` — build wikilink index with hidden-dir exclusion and Obsidian resolution rules
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder/src/pykoclaw_pykofinder/transform.py` — rewrite wikilinks and Markdown links/images to pykofinder URLs
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder/src/pykoclaw_pykofinder/__init__.py` — wire plugin class, lazy index creation, and transform hook
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder/tests/test_index.py` — cover resolution precedence, path-qualified names, and hidden directories
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-pykofinder/tests/test_transform.py` — cover link rewriting, fragments, aliases, encoding, and unresolved links

### WhatsApp repo — `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp`

- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp/src/pykoclaw_whatsapp/__init__.py` — load all plugins, run all migrations, compose response transformers, pass transformer to connection
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp/src/pykoclaw_whatsapp/images.py` — detect Markdown image URLs in addition to local image paths
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp/src/pykoclaw_whatsapp/segments.py` — emit `url` image refs in message order
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py` — forward `response_transformer` and add URL-download image sending
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp/tests/test_wa_segments.py` — cover URL image segmentation ordering and non-image HTTP links
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-whatsapp/tests/test_connection.py` — cover transformed dispatch and URL image sending fallback/logging

### Matrix repo — `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix`

- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix/src/pykoclaw_matrix/__init__.py` — load all plugins, run all migrations, compose response transformers, pass transformer to connection
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix/src/pykoclaw_matrix/images.py` — detect Markdown image URLs in addition to local image paths
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix/src/pykoclaw_matrix/segments.py` — emit `url` image refs while preserving Mermaid/file ordering
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix/src/pykoclaw_matrix/connection.py` — forward `response_transformer` and add async URL-download image sending
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix/tests/test_segments.py` — cover URL images alongside Mermaid and local files
- [ ] `/home/agent/prg/pykoclaw-worktrees/pykoclaw-pykofinder/pykoclaw-matrix/tests/test_connection.py` — cover transformed dispatch and URL image upload fallback/logging

## Non-goals (v1)

- No file-watcher / live index refresh (index built once at plugin init)
- No pykofinder search API calls (all resolution is local filesystem)
- No Slack image attachment (Slack plugin does not yet attach images)
- No ACP-specific changes (ACP passes text to Mitto which renders Markdown
  natively — pykofinder URLs in ACP responses become clickable links for free)
- No agent system-prompt modifications to encourage wikilink usage
- No caching of downloaded images across messages
- No support for `[[Note]]` → embed rendering (only link, not full content embed)

---

## Open decisions

- [ ] **`_send_image` refactor in WhatsApp**: the current signature takes a
      `Path`. Task 6 needs a bytes-based variant. Options: (a) add
      `_send_image_bytes(jid, data, name)` alongside the existing method; (b)
      change `_send_image` to accept `Path | bytes`. Option (a) is safer — no
      churn in existing call sites.
- [ ] **Download timeout and size limit**: what timeout and max-bytes cap should
      apply when downloading a pykofinder image URL? Suggested: 15 s timeout,
      20 MB cap. Configurable via `PykofinderSettings`? Probably not necessary
      for v1 — hard-code sensible defaults.
- [ ] **`compose_transformers` location**: can live in `pykoclaw.plugins` (small
      utility, used by channel plugins) or in `pykoclaw-messaging`. Core is the
      right place since the plugin protocol lives there.
- [ ] **Priority of `transform_response` vs other future transformers**: the
      order in which plugins' `transform_response` methods are chained follows
      plugin load order (entry-point discovery order). For v1, pykofinder is the
      only transformer plugin, so order is moot. Document it for future implementors.
