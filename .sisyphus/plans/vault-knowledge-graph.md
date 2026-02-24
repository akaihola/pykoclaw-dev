# Vault Knowledge Graph

## Status: Backlog

## Priority: 5

## TL;DR

> **Quick Summary**: Encode typed relationships and observations directly in the
> Obsidian vault's `.md` files using Dataview inline fields and tagged
> observations. Index them in a disposable SQLite database for fast querying and
> (later) semantic search. The vault stays the source of truth — human-readable,
> Syncthing-synced. The index is local and disposable.
>
> **Deliverables**:
>
> - Vault parser that extracts Dataview inline fields (`key:: value`) and tagged observations (`#category text`)
> - SQLite index with entities, relations, observations, and FTS5 full-text search
> - `pykoclaw-memory` plugin exposing MCP tools: `search_knowledge`, `traverse_graph`, `store_observation`, `reindex`
> - Later: embedding-based semantic search via sqlite-vec
>
> **Estimated Effort**: Large
> **Depends On**: —

---

## Context

### Current State

Agent knowledge lives in two places: `MEMORY.md` kernel (cross-session
preferences) and project files in the Obsidian vault. There is no structured way
to query relationships between entities (services, machines, projects) or search
observations by category. The agent re-reads files each session.

### Why This Matters

A queryable knowledge graph lets the agent answer "what depends on CCM?" or "what
operational lessons do we have about pykoclaw?" without scanning every file. It
also opens the door to semantic search — finding relevant context by meaning, not
just keywords.

---

## Design

### Notation: Dataview inline fields

Established Obsidian convention. Trivially parseable (`^(\w[\w-]*):: (.+)$`).
Wikilinks inside fields are clickable. Dataview plugin can query them too.

```markdown
# CCM

runs-on:: [[gogo]]
depended-on-by:: [[pykoclaw-scheduler-tyko]], [[mitto-web]]
monitored-by:: [[CCM 429 watcher]]
```

### Categorized observations

Tagged observation lists for facts that aren't relationships:

```markdown
## Observations
- #config Listens at `localhost:13456`
- #operational Routes via `ANTHROPIC_BASE_URL` / `ANTHROPIC_API_KEY` env vars
- #lesson Single point of failure for all agent sessions
```

Tags (`#config`, `#operational`, `#lesson`) are native Obsidian — searchable,
filterable in the tag pane, render correctly in reading and editing modes.

### Index architecture

```
┌──────────────────────────────────────────┐
│        Obsidian vault (.md files)         │
│  Source of truth. Human-readable.         │
└──────────────┬───────────────────────────┘
               │ parse on demand / watch
┌──────────────▼───────────────────────────┐
│         SQLite index (binary)             │
│                                           │
│  entities    (path, name, type, tags)     │
│  relations   (source, target, rel_type)   │
│  observations(entity, category, text)     │
│  fts5_index  (full-text on observations)  │
│  ┈┈┈┈┈ later ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈  │
│  embeddings  (entity_id, vector)          │
│  vec_index   (sqlite-vec cosine search)   │
└──────────────┬───────────────────────────┘
               │ query
┌──────────────▼───────────────────────────┐
│      pykoclaw-memory plugin (in-process)  │
│                                           │
│  MCP tools:                               │
│    search_knowledge  (FTS5 / semantic)    │
│    traverse_graph    (follow relations)   │
│    store_observation (write to .md file)  │
│    reindex           (rebuild from vault) │
└───────────────────────────────────────────┘
```

Syncthing syncs the `.md` files; the index stays local per machine.

---

## Open Questions

- Which observation categories beyond `#config`, `#operational`, `#lesson`?
- Should the indexer run as a pykoclaw plugin or a standalone watcher?
- Embedding model choice for the semantic search phase?
