# Set Claude Code cwd to data_dir instead of per-conversation subdirectory

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development
> (if subagents available) or superpowers:executing-plans to implement this plan.
> Steps use checkbox (`- [ ]`) syntax for tracking.

## Status: Done

## Completed: 2026-03-25

**Goal:** Change the Claude Code subprocess `cwd` from
`{data_dir}/conversations/{name}/` to `{data_dir}/` so the agent operates in
the workspace root where `.claude/`, `CLAUDE.md`, skills, and user files
actually live – instead of a throwaway empty subdirectory.

**Architecture:** The `conversations/` subdirectory tree is a vestige of the
earliest pykoclaw prototype (Feb 9, 2026) which treated each conversation as a
mini-project. Claude Code walks up from `cwd` to find settings, so
`.claude/` and `CLAUDE.md` in `data_dir` _are_ found today – but the agent's
tool operations (Bash, Read, Write) resolve relative paths against the wrong
directory. The fix is straightforward: stop creating `conversations/{name}/`
and pass `data_dir` as `cwd`. The `cwd` column in the `conversations` DB table
becomes the `data_dir` path (unchanged across conversations).

**Tech Stack:** Python, pytest, pytest-asyncio, SQLite

**Repos touched:** `pykoclaw` (core), `pykoclaw-acp`, `pykoclaw-chat`

Pi-Session: 016c218b-0d12-4516-b832-f46b1536a39d
Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-25T06-57-07-856Z_016c218b-0d12-4516-b832-f46b1536a39d.jsonl

---

## Background

### What `conv_dir` does today

Three code sites create `{data_dir}/conversations/{conversation_name}/` and
pass it as `cwd` to `ClaudeAgentOptions`:

| Site              | File                                           | Also does                                                 |
| ----------------- | ---------------------------------------------- | --------------------------------------------------------- |
| `query_agent()`   | `pykoclaw/src/pykoclaw/agent_core.py`          | Core agent loop                                           |
| `_spawn_worker()` | `pykoclaw-acp/src/pykoclaw_acp/worker_pool.py` | ACP process pool                                          |
| `_run_chat()`     | `pykoclaw-chat/src/pykoclaw_chat/__init__.py`  | Interactive REPL; also creates empty per-conv `CLAUDE.md` |

### Why the change is safe

1. **Settings discovery is unaffected.** Claude Code walks _up_ the directory
   tree from `cwd` to find `CLAUDE.md`, `.claude/CLAUDE.md`, and
   `.claude/rules/`. Moving `cwd` from `data_dir/conversations/name/` to
   `data_dir/` means settings are found _directly_ (zero-hop) instead of two
   hops up.

2. **The `cwd` column in the `conversations` DB table is informational only.**
   It is written by `upsert_conversation()` and read only by the `session_meta`
   MCP tool (exposed as metadata). It never drives the choice of `cwd` for
   the next agent call.

3. **No code reads from or deliberately writes meaningful data to
   `conversations/{name}/`.** The only contents found in existing dirs are
   accidental tool artifacts (`.ruff_cache/`, `.pytest_cache/`, `.wrangler/`,
   TLS certs) and one scheduled-task output (`self-management-digests/`). The
   scheduled task uses relative file paths from its `cwd`; after this change it
   will write to `data_dir/` instead, which is actually more useful.

4. **The chat plugin's per-conversation `CLAUDE.md`** (`conv_dir/CLAUDE.md`)
   is created but never populated by anything. All real instructions are in
   `data_dir/CLAUDE.md` (read by the chat plugin and passed as
   `system_prompt`). Removing the per-conv file is a no-op.

### What changes for end users

- The agent's Bash/Read/Write/Edit tools will resolve relative paths against
  the workspace root (`data_dir`) instead of an ephemeral empty directory.
  This is strictly better.
- No new `conversations/` directories will be created. Existing ones can be
  cleaned up manually (a cleanup command is out of scope for this plan).
- The `cwd` field returned by the `session_meta` MCP tool will show `data_dir`
  instead of the per-conversation path.

---

## Task 1: Change `query_agent()` in `agent_core.py`

**Files:**

- Modify: `pykoclaw/src/pykoclaw/agent_core.py`
- Test: `pykoclaw/tests/test_agent_core.py`

### Step 1.1 – Write failing test: `cwd` passed to SDK equals `data_dir`

- [ ] Add a test in `pykoclaw/tests/test_agent_core.py` that calls
      `query_agent()` with a `tmp_path` as `data_dir` and a conversation name,
      patches `ClaudeSDKClient` with a fake, and asserts that
      `ClaudeAgentOptions.cwd` was set to `str(data_dir)` (not
      `str(data_dir / "conversations" / name)`).

- [ ] Run: `uv run pytest pykoclaw/tests/test_agent_core.py::<test_name> -v`
      – expect FAIL (current code passes `conversations/{name}`).

### Step 1.2 – Write failing test: no `conversations/` directory created

- [ ] Add a test asserting that after `query_agent()` returns, the path
      `data_dir / "conversations" / conversation_name` does **not** exist.

- [ ] Run test – expect FAIL (current code calls `conv_dir.mkdir()`).

### Step 1.3 – Implement: change `cwd` and remove `mkdir`

- [ ] In `query_agent()`:
  - Remove the two lines that create `conv_dir` (`conv_dir = ...` /
    `conv_dir.mkdir(...)`).
  - Change `cwd=str(conv_dir)` → `cwd=str(data_dir)` in `ClaudeAgentOptions`.
  - Change `str(conv_dir)` → `str(data_dir)` in the `upsert_conversation()`
    call.

- [ ] Run: `uv run pytest pykoclaw/tests/test_agent_core.py -v` – expect all
      PASS including the two new tests.

### Step 1.4 – Commit

- [ ] `git add -A && git commit -m "fix(agent_core): set cwd to data_dir instead of per-conversation subdir"`

---

## Task 2: Change `_spawn_worker()` in `worker_pool.py`

**Files:**

- Modify: `pykoclaw-acp/src/pykoclaw_acp/worker_pool.py`
- Test: `pykoclaw-acp/tests/test_worker_pool.py`

### Step 2.1 – Write failing test: worker config `cwd` equals `data_dir`

- [ ] Add a test that spawns a worker via the pool (using the existing mock
      worker script pattern), then inspects the `WorkerConfig.cwd` received by the
      mock worker. Assert it equals `str(data_dir)` rather than
      `str(data_dir / "conversations" / conv_name)`.

  _Implementation note:_ The existing `resume_echo_worker.py` pattern already
  parses the config JSON from stdin. Write a similar mock that echoes
  `config["cwd"]` as text.

- [ ] Run test – expect FAIL.

### Step 2.2 – Write failing test: no `conversations/` directory created

- [ ] Assert `data_dir / "conversations" / conv_name` does not exist after
      `pool.send()`.

- [ ] Run test – expect FAIL.

### Step 2.3 – Implement: change `cwd` and remove `mkdir` in `_spawn_worker()`

- [ ] Remove `conv_dir = ...` and `conv_dir.mkdir(...)`.
- [ ] Change `cwd=str(conv_dir)` → `cwd=str(self._data_dir)` in
      `WorkerConfig(...)`.

- [ ] Run: `uv run pytest pykoclaw-acp/tests/test_worker_pool.py -v` – expect
      all PASS.

### Step 2.4 – Commit

- [ ] `git add -A && git commit -m "fix(acp): set worker cwd to data_dir instead of per-conversation subdir"`

---

## Task 3: Change `_run_chat()` in `pykoclaw-chat`

**Files:**

- Modify: `pykoclaw-chat/src/pykoclaw_chat/__init__.py`
- Test: `pykoclaw-chat/tests/test_chat_plugin.py`

### Step 3.1 – Write failing test: no per-conversation dir or `CLAUDE.md` created

- [ ] Add a test that calls `_run_chat()` (with the agent query patched to
      immediately return) and asserts:
  1. `data_dir / "conversations" / name` does not exist.
  2. No `CLAUDE.md` was created inside a `conversations/` subdirectory.

  _Note:_ `_run_chat()` blocks on `input()`. Patch `builtins.input` to raise
  `EOFError` immediately, and patch `query_agent` to prevent SDK calls.

- [ ] Run test – expect FAIL.

### Step 3.2 – Implement: remove per-conversation dir and CLAUDE.md creation

- [ ] Remove the `conv_dir = ...` / `conv_dir.mkdir(...)` block.
- [ ] Remove the `conv_claude_md = conv_dir / "CLAUDE.md"` block (creation of
      empty per-conversation CLAUDE.md).
- [ ] The `data_dir / "CLAUDE.md"` (global) creation stays – it is still read
      and used as `system_prompt`.

- [ ] Run: `uv run pytest pykoclaw-chat/tests/test_chat_plugin.py -v` – all PASS.

### Step 3.3 – Commit

- [ ] `git add -A && git commit -m "fix(chat): remove per-conversation dir and CLAUDE.md creation"`

---

## Task 4: Update `upsert_conversation()` callers for consistency

The `cwd` parameter in `upsert_conversation()` is now always `str(data_dir)`.
There are also callers in the retry path of `dispatch.py` that pass `str(data_dir)`
directly – verify these are consistent.

**Files:**

- Inspect: `pykoclaw-messaging/src/pykoclaw_messaging/dispatch.py`
- Test: `pykoclaw-messaging/tests/test_dispatch.py`

### Step 4.1 – Check dispatch.py retry path

- [ ] Read the `except ProcessError` block in `dispatch_to_agent()`. It calls
      `upsert_conversation(db, conversation_name, None, str(data_dir))`. This
      already passes `data_dir` (not `conv_dir`), so no code change is needed.
      Confirm and move on.

### Step 4.2 – Run existing dispatch tests

- [ ] Run: `uv run pytest pykoclaw-messaging/tests/test_dispatch.py -v` – all
      PASS (these tests use `tmp_path` as `data_dir` and mock `query_agent`, so
      they don't create `conversations/` dirs).

### Step 4.3 – Commit (only if any change was needed)

---

## Task 5: Update documentation and memory files

**Files:**

- Modify: `CLAUDE.md` (workspace root)
- Modify: `.memory/INDEX.md` (if a new memory note is added)
- Optionally create: `.memory/cwd-is-data-dir.md`

### Step 5.1 – Update `CLAUDE.md`

- [ ] In the **"Important gotchas"** section of `/home/agent/prg/pykoclaw-dev/CLAUDE.md`:
  - Remove or update any references to `conversations/{name}` as the agent's
    working directory.
  - The bullet about `PYKOCLAW_DATA` controlling the data directory stays.

### Step 5.2 – Update the `setting_sources` memory note

- [ ] In `.memory/claude-sdk-setting-sources.md`:
  - Update the "Current setting" section to note that `cwd` is now `data_dir`
    (the workspace root), so project settings are found directly (no directory
    walk needed).

### Step 5.3 – Create memory note (optional)

- [ ] If this change has non-obvious implications worth remembering, create
      `.memory/cwd-is-data-dir.md` with a brief note. Update `.memory/INDEX.md`.

### Step 5.4 – Commit

- [ ] `git add -A && git commit -m "docs: update CLAUDE.md and memory notes for cwd change"`

---

## Task 6: Full test suite verification

### Step 6.1 – Run all tests

- [ ] Run: `uv run pytest pykoclaw/tests/ -v`
- [ ] Run: `uv run pytest pykoclaw-acp/tests/ -v` (from pykoclaw-acp dir if needed)
- [ ] Run: `uv run pytest pykoclaw-messaging/tests/ -v`
- [ ] Run: `uv run pytest pykoclaw-chat/tests/ -v`
- [ ] All PASS.

### Step 6.2 – Backlog update

- [ ] Run: `bin/update-backlog.sh`

---

## Out of scope

- **Cleanup of existing `conversations/` directories.** Old directories are
  harmless (empty or contain only cache artifacts). A cleanup script or
  migration can be done separately.
- **Removing the `cwd` column from the `conversations` table.** It still
  serves an informational purpose in `session_meta`. Its value simply
  changes from per-conversation to per-workspace.
- **Changing the `conversations/` path used by the `self-management-digests`
  scheduled task.** That task uses absolute paths in its prompt
  (`~/coleaders/docs/poiminnat/YYYY-MM.md`). The digest files in
  `conversations/self-management-digests/` were written by a previous
  version of the task prompt using relative paths; new runs will write to
  `data_dir/` if they use relative paths, which is correct.
