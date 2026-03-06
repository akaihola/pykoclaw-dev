# Pykofinder Link Translation Plugin

## Status: Backlog

## Priority: 10

## TL;DR

> **Quick Summary**: Add a `pykoclaw-pykofinder` plugin that post-processes LLM
> responses and rewrites internal file links (Markdown links, image links, and
> Obsidian-style wikilinks) to point to files served by a running pykofinder
> instance. The transformation happens after the agent replies but before
> channel-specific formatting. Channel plugins (WhatsApp, Matrix) are extended
> to recognise HTTP image URLs in the response and download-then-attach them,
> mirroring how they already handle local file paths.
>
> **Deliverables**:
>
> - `pykoclaw-pykofinder/` — new uv workspace member + package
> - `transform_response` plugin hook in core + dispatch pipeline
> - Link transformation engine: relative links, absolute links, wikilinks
> - Obsidian-compatible wikilink index with full wikilink syntax support
> - URL image segment support in `pykoclaw-whatsapp` (download + attach)
> - URL image segment support in `pykoclaw-matrix` (download + attach)
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

### Current image handling

Both `pykoclaw-whatsapp` and `pykoclaw-matrix` split agent responses into
interleaved text and image segments (`split_segments()`). They currently recognise
only **absolute local file paths** as image segments (checked with `Path.is_file()`).
After the pykofinder transform turns `![alt](local.png)` into an HTTP URL, the
existing code no longer sees it as an image segment. This must be fixed.

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

A new method is added to the plugin protocol:

```
PykoClawPlugin.transform_response(text: str) -> str
```

`PykoClawPluginBase` provides an identity default. `dispatch_to_agent()` in
`pykoclaw-messaging` gains an optional `response_transformer: Callable[[str], str] | None`
parameter. After assembling `full_text` from the agent stream but before
returning `DispatchResult`, it applies the transformer:

```
full_text = response_transformer(full_text)   # if transformer is not None
```

Channel plugins build the composite transformer by loading all plugins and
chaining their `transform_response` methods, then pass it into `dispatch_to_agent`.

### How channel plugins pass the transformer

Each channel plugin's CLI `run` command currently calls `run_db_migrations` with
just its own plugin. It should instead call `load_plugins()` to get ALL loaded
plugins, run DB migrations for all of them, and build a composite transformer:

```
all_plugins = load_plugins()
run_db_migrations(db, all_plugins)
transformer = compose_transformers(all_plugins)   # chains transform_response calls
```

`compose_transformers` is a small helper (can live in `pykoclaw.plugins`) that
returns a single `Callable[[str], str]` that applies each plugin's
`transform_response` in registration order.

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
- If the path starts with `/` → it is an absolute local path → construct
  pykofinder URL using the path as-is
- Otherwise → treat as relative to `workspace_root` → join and construct URL

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

## URL image segments in channel plugins

After the pykofinder transform, image references in the response text are HTTP
URLs, not local paths. Both channel plugins must be extended to handle them.

### Changes to `pykoclaw-whatsapp`

**`images.py`**: add a compiled regex `IMAGE_URL_MD_RE` that matches Markdown
image syntax `![alt](https?://url)`, capturing the URL. This regex must not
overlap with the existing `IMAGE_PATH_RE` (which only matches paths starting
with `/`).

**`segments.py`**: extend `split_segments()` to also scan for `IMAGE_URL_MD_RE`
matches. For each match, add an `ImageRef(kind="url", source=url_string)` marker.
Extend `ImageRef.kind` to `Literal["file", "url"]`.

**`connection.py`**: in `_send_message()`, add a branch for `ref.kind == "url"`:
download the URL with `httpx` (synchronous `httpx.get`, since `_send_message`
is sync) or via `urllib.request.urlopen`, read the bytes, infer MIME type from
the URL extension using `mimetypes`, and pass bytes to `_send_image()`. Log on
failure, do not raise.

### Changes to `pykoclaw-matrix`

**`images.py`**: same — add `IMAGE_URL_MD_RE`.

**`segments.py`**: `ImageRef` already has `kind: Literal["mermaid", "file"]`.
Extend to `Literal["mermaid", "file", "url"]`. Add URL image detection
(same `IMAGE_URL_MD_RE` scan) alongside existing mermaid and file scans.

**`connection.py`**: in `_send_message()`, add a branch for `ref.kind == "url"`:
download asynchronously with `httpx.AsyncClient.get()` (Matrix plugin is fully
async), infer MIME type, call `_send_image()` with the bytes.

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
