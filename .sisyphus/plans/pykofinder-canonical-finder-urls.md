# Pykofinder Canonical Finder URLs and Relative-Link Semantics

## Status: In Progress

## Started: 2026-03-08

## Priority: 11

## TL;DR

> **Quick Summary**: Move pykofinder's public finder URLs for workspace-local files
> from legacy absolute-path query links (`/f/?path=/abs/path.md`) to canonical
> mount-relative path URLs (`/f/<mount>/relative/path.md`). Keep `/w/` path-based
> for all workspace-local static assets and ensure the pykoclaw pykofinder plugin
> emits path-based `/f/` and `/w/` URLs whenever a target is representable under
> the workspace mount. Retain legacy `/f/?path=` only as a compatibility fallback
> for non-workspace viewer links.
>
> **Primary user-visible win**: relative markdown links such as
> `[link](subdir/other-file.md)` begin to behave like normal hierarchical web links
> when rendered in previews, instead of breaking because the current document URL is
> query-state rather than a path.
>
> **Deliverables**:
>
> - `pykofinder` canonical `/f/<mount>/<relative>` route support
> - Legacy `/f/?path=` compatibility redirect/fallback
> - Path-based browser URL sync and popstate handling
> - Canonical markdown preview links for docs and assets
> - VFS URL sync preserved as `/f/<mount>/<relative>?vpath=...`
> - `pykoclaw-pykofinder` emits path-based `/f/` + `/w/` URLs for workspace-local files
> - Updated tests, docs, and migration notes in both repos
>
> **Estimated Effort**: Medium
> **Depends On**: —

---

## Context

### Current pykofinder behavior

`pykofinder` already serves static files via named mounts under path-based URLs:

- `/w/<mount>/<relative/path>`

But finder/viewer URLs still rely on a query parameter carrying an absolute path:

- `/f/?path=/absolute/path/to/file.md`

That asymmetry leaks into multiple layers:

- browser history sync in `src/pykofinder/styles.py`
- deep-link entry route in `src/pykofinder/app.py`
- markdown relative-link normalization in `src/pykofinder/rendering.py`
- pykoclaw's pykofinder transform plugin in `/home/agent/prg/pykoclaw-dev/pykoclaw-pykofinder`

### Why this matters

A query-style URL has no hierarchical base path semantics, so relative links in a
markdown preview cannot behave like normal web links. The current document might be
shown at something like `/f/?path=%2Fhome%2Fagent%2Fnotes%2Fguide.md`, and the browser
cannot resolve `[next](subdir/next.md)` relative to that in the intuitive way.

By moving workspace-local viewer URLs to `/f/<mount>/<relative/path>`, finder URLs gain:

- normal browser path semantics for relative links
- cleaner and more shareable URLs
- parity with `/w/<mount>/<relative/path>`
- less absolute-path leakage in the address bar

### Compatibility requirement

Not every absolute path is representable under the active workspace mount. The user
explicitly wants legacy fallback retained for such paths:

- workspace-local, mount-representable targets → canonical path-based `/f/` and `/w/`
- non-workspace viewer targets → legacy `/f/?path=<absolute>` fallback remains allowed
- `/w/` must remain path-based only; do not introduce or keep a `/w/?path=` public form

---

## Scope

### In scope

#### Repo 1 — `/home/agent/prg/pykofinder`

- Canonical `/f/<mount>/<relative>` public route behavior
- Legacy `/f/?path=` compatibility handling
- Browser history sync and keyboard/popstate URL correctness
- Markdown preview href generation for docs/assets
- VFS URL preservation with canonical filesystem path + `vpath`
- README / ISSUES / TASKS updates
- Browser and pytest coverage for regressions

#### Repo 2 — `/home/agent/prg/pykoclaw-dev/pykoclaw-pykofinder`

- Canonical path-based URL emission for workspace-local viewer/static links
- Legacy `/f/?path=` fallback for non-workspace viewer links only
- Explicitly no `/w/?path=` output
- README and pytest updates

### Out of scope for this slice

- Replacing internal plumbing endpoints such as `/click?path=...`, `/restore?path=...`,
  or `/raw?path=...` unless that simplification naturally falls out with low risk
- Multi-workspace canonicalization beyond current named mount rules
- Any pykoclaw channel-plugin behavior changes unrelated to URL generation

---

## Canonical URL contract

### Public URLs

- Finder root: `/f/`
- Finder file/dir: `/f/<mount>/<relative/path>`
- Finder VFS location: `/f/<mount>/<relative/file>?vpath=<provider-subpath>`
- Static/raw asset: `/w/<mount>/<relative/path>`

### Compatibility input

- Legacy finder input remains accepted:
  - `/f/?path=<absolute-path>[&vpath=...]`
- If the absolute path is representable under a known mount, pykofinder should redirect
  to the canonical `/f/<mount>/<relative/path>[?vpath=...]` URL.
- If the absolute path is not representable under a known mount but is still safe and
  reachable under the current compatibility rules, keep serving via legacy `/f/?path=`.

### Canonicalization rules

- Prefer the root mount (`ROOT.name`) when the resolved target lives under `ROOT`.
- Otherwise match direct symlink child mounts deterministically.
- The same mount-selection rules should power both `/f/` and `/w/` URL construction.

---

## Work plan

### Phase 1 — Red tests in `pykofinder`

1. Add a new issue to `/home/agent/prg/pykofinder/ISSUES.md` and a matching `[~]`
   task to `/home/agent/prg/pykofinder/TASKS.md`.
2. Add failing route tests in `/home/agent/prg/pykofinder/tests/test_routes_new.py`:
   - `/f/<root-mount>/<relative>` serves shell with deep-link bootstrap
   - `/f/<bookmark-mount>/<relative>` serves shell with deep-link bootstrap
   - `/f/?path=<workspace-local-abs>` redirects to canonical `/f/<mount>/<relative>`
   - redirect preserves `vpath`
   - invalid mount path returns 404
3. Add failing rendering/JS tests in `/home/agent/prg/pykofinder/tests/test_rendering.py`:
   - markdown doc links render canonical `/f/<mount>/...`
   - markdown asset/image links render canonical `/w/<mount>/...`
   - generated output contains no `/w/?path=`
   - `COLUMN_JS` no longer pushes `/f/?path=` for workspace-local navigation
4. Add or update VFS tests for canonical URL shape with `?vpath=` preserved.

### Phase 2 — Green implementation in `pykofinder`

1. Add shared mount-to-URL helpers in `/home/agent/prg/pykofinder/src/pykofinder/app.py`.
2. Refactor `_web_url()` to share canonical path generation logic with the new finder URL helper.
3. Update `/f/` route handling to support canonical path URLs and legacy redirects/fallback.
4. Update server-rendered column links to include canonical finder URLs for history sync.
5. Update `src/pykofinder/styles.py` to push canonical URLs and keep root as `/f/`.
6. Update markdown rendering helpers in `src/pykofinder/rendering.py` so preview links use
   canonical `/f/` and `/w/` public URLs.
7. Run targeted pytest, then full pytest under shell timeout.
8. Run browser regression coverage for keyboard URL sync and relative-link navigation.

### Phase 3 — Red tests in `pykoclaw-pykofinder`

1. Update `/home/agent/prg/pykoclaw-dev/pykoclaw-pykofinder/tests/test_transform.py` so
   workspace-local viewer links expect `/f/<workspace>/<relative>`.
2. Keep image/static expectations on `/w/<workspace>/<relative>`.
3. Add explicit fallback tests:
   - non-workspace document link → legacy `/f/?path=<absolute>`
   - non-workspace image/static link → never `/w/?path=`; either remains local/native or
     only rewrites when canonically representable
4. Add fragment-preservation assertions on canonical viewer URLs.

### Phase 4 — Green implementation in `pykoclaw-pykofinder`

1. Update `src/pykoclaw_pykofinder/transform.py` URL builders.
2. Canonicalize any workspace-local absolute path input to mount-relative `/f/` or `/w/`.
3. Keep legacy `/f/?path=` fallback only for non-workspace viewer links.
4. Ensure no code path emits `/w/?path=`.
5. Run targeted pytest, then full plugin test suite.

### Phase 5 — Docs and rollout

1. Update `/home/agent/prg/pykofinder/README.md`, `ISSUES.md`, and `TASKS.md`.
2. Update `/home/agent/prg/pykoclaw-dev/pykoclaw-pykofinder/README.md`.
3. Update this backlog plan and regenerate `/home/agent/prg/pykoclaw-dev/.sisyphus/BACKLOG.md` if needed.
4. Commit each logical checkpoint with conventional commits.
5. After the pykofinder batch lands, restart the user service:
   - `systemctl --user restart pykofinder.service`

---

## Testing strategy

### `pykofinder`

#### Unit + route tests

- canonical `/f/<mount>/<relative>` success cases
- legacy `/f/?path=` redirect and fallback cases
- markdown href generation for docs and assets
- JS string assertions proving canonical history sync
- VFS canonical URL preservation with `vpath`

#### Browser verification

- open a markdown file with relative links
- click a rendered relative markdown link to another note
- assert preview updates and address bar uses canonical `/f/<mount>/...`
- re-run ArrowLeft/ArrowRight keyboard flow and ensure URL remains canonical

### `pykoclaw-pykofinder`

- canonical viewer URL output for workspace-local files
- canonical `/w/` output for workspace-local images/static files
- non-workspace viewer fallback to `/f/?path=`
- explicit absence of `/w/?path=` output
- fragment preservation

---

## Commit plan

### Repo: `/home/agent/prg/pykofinder`

1. `test: add red coverage for canonical finder urls`
2. `feat: canonicalize finder urls to mount-relative paths`
3. `test: cover canonical markdown and vfs urls`
4. `docs: update finder url contract and migration notes`

### Repo: `/home/agent/prg/pykoclaw-dev/pykoclaw-pykofinder`

1. `test: update viewer url expectations to canonical finder paths`
2. `feat: emit canonical finder urls for workspace-local links`
3. `docs: document canonical finder url behavior`

---

## Notes / design constraints

- Internal helper endpoints can continue using absolute-path query params during this slice if
  that reduces risk; the priority is to fix public browser-visible URLs first.
- Treat “workspace-local and mount-representable” as the canonicalization boundary, not whether
  the original input string happened to be relative or absolute.
- `pykofinder` must ship compatibility support before the pykoclaw plugin starts emitting the
  new canonical viewer URLs.
- This change should simplify the public model: workspace-local links are always path-based;
  only non-workspace viewer fallback uses legacy `/f/?path=`.
