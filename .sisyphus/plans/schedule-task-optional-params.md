# Fix schedule_task tool schema: optional parameters

## Status: Done

## Completed: 2026-02-16

## TL;DR

> **Quick Summary**: The `schedule_task` MCP tool schema declares all parameters
> as required, but `target_conversation` and `context_mode` are meant to be
> optional. This causes the agent (Tyko) to always provide them — or fail when
> trying to omit them. Fix the schema, align the `context_mode` default across
> layers, and add a "failing test first" rule to CLAUDE.md.
>
> **Deliverables**:
> - Fixed tool schema with correct required/optional fields
> - Aligned `context_mode` default to `"group"` across model, DB, and handler
> - Failing-then-passing test for the schema
> - New testing rule in CLAUDE.md
> - Memory file documenting the SDK schema gotcha
>
> **Estimated Effort**: Quick
> **Parallel Execution**: NO — sequential (TDD red→green requires ordering)
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 → Task 5

---

## Context

### Original Request

Tyko (the pykoclaw agent) fails when calling `schedule_task` without providing
`target_conversation`. The user also requested adding a rule to CLAUDE.md:
always reproduce a bug with a failing test before fixing it.

### Interview Summary

**Key Discussions**:
- `target_conversation` is required in the tool schema but optional everywhere
  else (model, DB, handler)
- `context_mode` has the same schema problem PLUS a default mismatch: handler
  says `"group"`, model and DB say `"isolated"`
- User confirmed: fix both params, default `context_mode` to `"group"`

**Research Findings**:
- The `claude-agent-sdk` `@tool` decorator converts simple dict schemas
  (`{"name": str}`) by putting ALL keys into `"required"`. There is no way to
  mark a field as optional with the simple dict format.
- The SDK supports JSON Schema passthrough: if the dict has `"type"` and
  `"properties"` keys, it's used as-is. This is the correct fix.
- The `call_tool` handler in the SDK does NO validation — it passes args
  directly to the handler. The schema only affects what Claude sends.

### Metis Review

**Identified Gaps (addressed)**:
- `context_mode` default mismatch across layers → resolved: user chose `"group"`
- Two separate git repos for commits → planned as separate commit steps
- Missing test for the MCP tool schema → core deliverable of this plan

---

## Work Objectives

### Core Objective

Make `target_conversation` and `context_mode` optional in the `schedule_task`
MCP tool schema, align the `context_mode` default to `"group"` everywhere, and
establish the "failing test first" rule.

### Concrete Deliverables

- `pykoclaw/src/pykoclaw/tools.py` — schema changed to JSON Schema format
- `pykoclaw/src/pykoclaw/models.py` — `context_mode` default → `"group"`
- `pykoclaw/src/pykoclaw/db.py` — `context_mode` default → `"group"`
- `pykoclaw/tests/test_tools.py` — new test asserting schema correctness
- `CLAUDE.md` — new testing rule added
- `.memory/sdk-schema-gotcha.md` — gotcha documentation

### Definition of Done

- [ ] `uv run pytest pykoclaw/tests/test_tools.py -v` — all tests pass
- [ ] `uv run pytest pykoclaw/tests/` — full suite passes, no regressions
- [ ] `grep -c "failing test" CLAUDE.md` → output ≥ 1

### Must Have

- `target_conversation` and `context_mode` absent from `required` in generated
  JSON Schema
- `prompt`, `schedule_type`, `schedule_value` present in `required`
- `context_mode` defaults to `"group"` when omitted
- All existing tests still pass
- TDD workflow: test written and verified RED before fix applied

### Must NOT Have (Guardrails)

- DO NOT change handler logic in `tools.py` lines 35–58 — only the `@tool`
  decorator's schema argument
- DO NOT touch other tool schemas (`list_tasks`, `pause_task`, `resume_task`,
  `cancel_task`) — they are correct as-is
- DO NOT add JSON Schema property descriptions — the tool docstring covers it
- DO NOT restructure test files or add tests for other tools
- DO NOT fix the SDK's broken TypedDict path — out of scope

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL verification is executed by the agent using tools. No human action.

### Test Decision

- **Infrastructure exists**: YES (`pytest` + `pytest-asyncio`)
- **Automated tests**: YES (TDD — red then green)
- **Framework**: `uv run pytest`

### TDD Cycle

**RED**: Write test asserting schema correctness → run → must FAIL (because
schema currently makes all fields required).

**GREEN**: Fix the schema → run → must PASS.

**REFACTOR**: Not needed — change is minimal.

### Agent-Executed QA Scenarios (MANDATORY)

```
Scenario: Schema test fails before fix (RED)
  Tool: Bash
  Preconditions: Test written, schema NOT yet fixed
  Steps:
    1. uv run pytest pykoclaw/tests/test_tools.py -v -k "test_schedule_task_schema_optional"
    2. Assert: exit code 1
    3. Assert: output contains "FAILED"
  Expected Result: Test fails because target_conversation is currently in required
  Evidence: Terminal output captured

Scenario: Schema test passes after fix (GREEN)
  Tool: Bash
  Preconditions: Schema fixed in tools.py
  Steps:
    1. uv run pytest pykoclaw/tests/test_tools.py -v -k "test_schedule_task_schema_optional"
    2. Assert: exit code 0
    3. Assert: output contains "PASSED"
  Expected Result: Test passes, optional fields not in required list
  Evidence: Terminal output captured

Scenario: Full test suite regression check
  Tool: Bash
  Preconditions: All changes applied
  Steps:
    1. uv run pytest pykoclaw/tests/ -v
    2. Assert: exit code 0
    3. Assert: no FAILED lines in output
  Expected Result: All existing tests still pass
  Evidence: Terminal output captured
```

---

## Execution Strategy

### Sequential Execution (TDD requires ordering)

```
Task 1: Add testing rule to CLAUDE.md
    ↓
Task 2: Write failing schema test (RED)
    ↓
Task 3: Fix tool schema + context_mode defaults (GREEN)
    ↓
Task 4: Run full test suite + create memory file
    ↓
Task 5: Commit changes (two repos)
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|------------|--------|
| 1    | None       | 5      |
| 2    | None       | 3      |
| 3    | 2          | 4      |
| 4    | 3          | 5      |
| 5    | 1, 4       | None   |

Note: Tasks 1 and 2 are independent and could technically run in parallel, but
since this is a single-agent execution, sequential is fine.

### Agent Dispatch Summary

| Task | Recommended Agent |
|------|-------------------|
| 1–4  | `task(category="quick", load_skills=[], ...)` — single agent, sequential |
| 5    | `task(category="quick", load_skills=["git-master"], ...)` — two commits |

---

## TODOs

- [ ] 1. Add "failing test first" rule to CLAUDE.md

  **What to do**:
  - Open `CLAUDE.md` (workspace root)
  - In the `## Testing` section, after the line about test locations, add:
    ```
    - **Bug reports:** when a malfunction is reported, always reproduce the issue
      first by writing a failing test case before implementing the fix (red → green
      workflow).
    ```
  - Keep formatting consistent with existing bullet points

  **Must NOT do**:
  - Do not restructure other sections of CLAUDE.md
  - Do not change existing content

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single-line addition to an existing file
  - **Skills**: `[]`
    - No special skills needed for a markdown edit

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 2)
  - **Parallel Group**: Wave 1
  - **Blocks**: Task 5
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `CLAUDE.md:59-64` — The existing `## Testing` section where the new rule goes

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Testing rule exists in CLAUDE.md
    Tool: Bash
    Preconditions: CLAUDE.md edited
    Steps:
      1. grep "failing test" CLAUDE.md
      2. Assert: output contains "failing test case"
      3. grep "red.*green" CLAUDE.md
      4. Assert: output contains "red → green"
    Expected Result: Rule text present in file
    Evidence: grep output captured
  ```

  **Commit**: YES (groups with Task 5 — workspace root repo)
  - Message: `docs: add "failing test first" rule to testing section`
  - Files: `CLAUDE.md`
  - Pre-commit: none

---

- [ ] 2. Write failing schema test (RED)

  **What to do**:
  - Open `pykoclaw/tests/test_tools.py`
  - Add a new async test function `test_schedule_task_schema_optional` that:
    1. Creates a DB and conversation (use existing `db` fixture)
    2. Calls `make_mcp_server(db, "test")` to get the server config
    3. Gets the MCP server instance from `server["instance"]`
    4. Calls the `list_tools` request handler to get the tool list
    5. Finds the `schedule_task` tool in the list
    6. Asserts that `target_conversation` is in `properties` but NOT in `required`
    7. Asserts that `context_mode` is in `properties` but NOT in `required`
    8. Asserts that `prompt`, `schedule_type`, `schedule_value` ARE in `required`
  - Use `asyncio.run()` or `pytest.mark.asyncio` — follow whichever pattern the
    existing tests use (existing tests use sync functions, so use `asyncio.run()`
    for the async `list_tools` call)
  - **Run the test and verify it FAILS** — this is the RED step
  - The test MUST fail because the current schema puts all fields in `required`

  **Must NOT do**:
  - Do not modify the existing test functions
  - Do not fix the schema yet — the test must fail first
  - Do not add tests for other tools

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Adding one test function to an existing file
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential — must complete before Task 3
  - **Blocks**: Task 3
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `pykoclaw/tests/test_tools.py:10-12` — The `db` fixture to reuse
  - `pykoclaw/tests/test_tools.py:15-19` — Pattern for creating server and
    accessing it. `make_mcp_server` returns a dict with `"instance"` key.
  - `pykoclaw/tests/test_tools.py:22-29` — Shows how to import
    `ListToolsRequest` and check `instance.request_handlers`

  **API/Type References**:
  - The `list_tools` handler is registered at
    `instance.request_handlers[ListToolsRequest]`. Call it to get a list of
    `Tool` objects.
  - Each `Tool` has `.name` (str) and `.inputSchema` (dict with `"properties"`
    and `"required"` keys).
  - Import: `from mcp.types import ListToolsRequest`

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Test exists and FAILS (RED step)
    Tool: Bash
    Preconditions: Test written, schema NOT yet fixed
    Steps:
      1. uv run pytest pykoclaw/tests/test_tools.py::test_schedule_task_schema_optional -v
      2. Assert: exit code 1
      3. Assert: output contains "FAILED"
      4. Assert: output contains "AssertionError" (the test ran but assertion failed)
    Expected Result: Test runs but fails on assertion — proves the bug exists
    Evidence: Terminal output showing FAILED
  ```

  **Commit**: NO (uncommitted — will be committed with Task 3 after it passes)

---

- [ ] 3. Fix tool schema and context_mode defaults (GREEN)

  **What to do**:

  **3a. Fix the tool schema in `tools.py`**:
  - Change the `@tool` decorator's third argument (lines 27–33) from the simple
    dict format to JSON Schema format:

    Replace:
    ```python
    {
        "prompt": str,
        "schedule_type": str,
        "schedule_value": str,
        "context_mode": str,
        "target_conversation": str,
    },
    ```

    With:
    ```python
    {
        "type": "object",
        "properties": {
            "prompt": {"type": "string"},
            "schedule_type": {"type": "string"},
            "schedule_value": {"type": "string"},
            "context_mode": {"type": "string"},
            "target_conversation": {"type": "string"},
        },
        "required": ["prompt", "schedule_type", "schedule_value"],
    },
    ```

  - Do NOT change anything else in the file — handler logic stays the same

  **3b. Fix `context_mode` default in `models.py`**:
  - Line 17: change `context_mode: str = "isolated"` to
    `context_mode: str = "group"`

  **3c. Fix `context_mode` default in `db.py`**:
  - Line 276: change `context_mode: str = "isolated"` to
    `context_mode: str = "group"`

  **3d. Run the test and verify it PASSES** — this is the GREEN step:
  ```bash
  uv run pytest pykoclaw/tests/test_tools.py::test_schedule_task_schema_optional -v
  ```

  **Must NOT do**:
  - Do not change handler logic (`tools.py:35-58`)
  - Do not touch other tool schemas
  - Do not add JSON Schema descriptions to properties
  - Do not change the tool's name or description

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Three small edits across three files
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential — must follow Task 2
  - **Blocks**: Task 4
  - **Blocked By**: Task 2

  **References**:

  **Pattern References**:
  - `pykoclaw/src/pykoclaw/tools.py:27-33` — The schema to replace
  - `pykoclaw/src/pykoclaw/tools.py:40` — `args.get("target_conversation")` —
    confirms handler already handles None correctly
  - `pykoclaw/src/pykoclaw/tools.py:50` — `args.get("context_mode", "group")` —
    handler default is already `"group"`, matching the user's choice

  **API/Type References**:
  - `pykoclaw/src/pykoclaw/models.py:17` — `context_mode: str = "isolated"` —
    change to `"group"`
  - `pykoclaw/src/pykoclaw/db.py:276` — `context_mode: str = "isolated"` —
    change to `"group"`

  **Documentation References**:
  - The `claude-agent-sdk` `@tool` docstring says `input_schema` can be "A JSON
    Schema dictionary for full validation" — this is the format we're switching to

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Schema test passes after fix (GREEN step)
    Tool: Bash
    Preconditions: Schema fixed, defaults aligned
    Steps:
      1. uv run pytest pykoclaw/tests/test_tools.py::test_schedule_task_schema_optional -v
      2. Assert: exit code 0
      3. Assert: output contains "PASSED"
    Expected Result: Test passes — optional fields not in required list
    Evidence: Terminal output showing PASSED
  ```

  **Commit**: NO (committed together in Task 5)

---

- [ ] 4. Run full test suite and create memory file

  **What to do**:

  **4a. Run full test suite**:
  ```bash
  uv run pytest pykoclaw/tests/ -v
  ```
  Verify all tests pass — zero failures, zero errors.

  **4b. Create memory file** `.memory/sdk-schema-gotcha.md`:
  ```markdown
  # claude-agent-sdk: simple dict schemas make ALL fields required

  **Tags:** claude-agent-sdk, mcp, tools, schema
  **Related:** [tools.md]

  The `@tool` decorator's simple dict format (`{"name": str}`) converts ALL keys
  to required fields in JSON Schema. There is no way to mark a field optional.

  To make fields optional, use JSON Schema passthrough format:

      {
          "type": "object",
          "properties": {
              "required_field": {"type": "string"},
              "optional_field": {"type": "string"},
          },
          "required": ["required_field"],
      }

  The SDK checks for `"type"` + `"properties"` keys and passes the dict through
  as-is instead of converting it.

  [tools.md]: tools.md
  ```

  **4c. Update `.memory/INDEX.md`** to include the new file.

  **Must NOT do**:
  - Do not change any source files at this point
  - Do not skip the full test suite run

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Run tests + create one small memory file
  - **Skills**: `[]`
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential — must follow Task 3
  - **Blocks**: Task 5
  - **Blocked By**: Task 3

  **References**:

  **Pattern References**:
  - `.memory/INDEX.md` — The memory index to update
  - Any existing `.memory/*.md` file — Format to follow for memory files

  **Documentation References**:
  - `CLAUDE.md:79-109` — Memory system rules and file format

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Full test suite passes
    Tool: Bash
    Preconditions: All code changes from Tasks 2-3 applied
    Steps:
      1. uv run pytest pykoclaw/tests/ -v
      2. Assert: exit code 0
      3. Assert: output contains "passed" and no "FAILED"
    Expected Result: Zero failures, zero errors
    Evidence: Terminal output captured

  Scenario: Memory file exists with correct content
    Tool: Bash
    Preconditions: Memory file created
    Steps:
      1. cat .memory/sdk-schema-gotcha.md
      2. Assert: contains "simple dict schemas make ALL fields required"
      3. grep "sdk-schema-gotcha" .memory/INDEX.md
      4. Assert: file is listed in the index
    Expected Result: Memory file exists and is indexed
    Evidence: File content captured
  ```

  **Commit**: NO (committed together in Task 5)

---

- [ ] 5. Commit changes (two repositories)

  **What to do**:

  **5a. Commit in `pykoclaw/` subrepo** (code + test + memory):
  ```bash
  cd pykoclaw/
  git add src/pykoclaw/tools.py src/pykoclaw/models.py src/pykoclaw/db.py \
          tests/test_tools.py
  git commit -m "fix(tools): make target_conversation and context_mode optional in schedule_task schema

  The simple dict schema format in claude-agent-sdk marks ALL fields as
  required. Switch to JSON Schema passthrough format so target_conversation
  and context_mode are optional.

  Also aligns context_mode default to \"group\" across model, DB, and handler."
  ```

  **5b. Commit in workspace root** (CLAUDE.md + memory file):
  ```bash
  cd /home/agent/prg/pykoclaw-dev
  git add CLAUDE.md .memory/sdk-schema-gotcha.md .memory/INDEX.md
  git commit -m "docs: add failing-test-first rule and SDK schema gotcha memory"
  ```

  **Must NOT do**:
  - Do not `git push` — user will push when ready
  - Do not amend existing commits
  - Do not commit files outside the listed paths

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Two straightforward git commits
  - **Skills**: `["git-master"]`
    - `git-master`: Needed for proper commit workflow across two repos

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential — final task
  - **Blocks**: None
  - **Blocked By**: Tasks 1, 4

  **References**:

  **Documentation References**:
  - `CLAUDE.md:130-132` — "Each subdir is its own git repo. Commits go into the
    individual repos, not this workspace root (except for workspace-level files
    like this one)."

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Commits created in correct repos
    Tool: Bash
    Preconditions: All changes staged and committed
    Steps:
      1. cd pykoclaw/ && git log -1 --oneline
      2. Assert: message contains "make target_conversation and context_mode optional"
      3. cd /home/agent/prg/pykoclaw-dev && git log -1 --oneline
      4. Assert: message contains "failing-test-first rule"
      5. cd pykoclaw/ && git status
      6. Assert: working tree clean
      7. cd /home/agent/prg/pykoclaw-dev && git status
      8. Assert: working tree clean (for tracked files)
    Expected Result: Two clean commits in two repos
    Evidence: git log output captured
  ```

  **Commit**: YES (this IS the commit task)

---

## Commit Strategy

| After Task | Repo | Message | Files | Verification |
|------------|------|---------|-------|--------------|
| 5a | `pykoclaw/` | `fix(tools): make target_conversation and context_mode optional in schedule_task schema` | `tools.py`, `models.py`, `db.py`, `test_tools.py` | `uv run pytest pykoclaw/tests/` |
| 5b | workspace root | `docs: add failing-test-first rule and SDK schema gotcha memory` | `CLAUDE.md`, `.memory/sdk-schema-gotcha.md`, `.memory/INDEX.md` | `grep "failing test" CLAUDE.md` |

---

## Success Criteria

### Verification Commands

```bash
# Schema test passes
uv run pytest pykoclaw/tests/test_tools.py::test_schedule_task_schema_optional -v
# Expected: PASSED

# Full suite passes
uv run pytest pykoclaw/tests/ -v
# Expected: all passed, 0 failures

# CLAUDE.md rule exists
grep "failing test" CLAUDE.md
# Expected: matching line found

# Memory file exists
cat .memory/sdk-schema-gotcha.md
# Expected: contains SDK schema documentation
```

### Final Checklist

- [ ] `target_conversation` optional in schema (not in `required`)
- [ ] `context_mode` optional in schema (not in `required`)
- [ ] `context_mode` default is `"group"` in model, DB, and handler
- [ ] `prompt`, `schedule_type`, `schedule_value` still required
- [ ] Handler logic in `tools.py:35-58` unchanged
- [ ] Other tool schemas unchanged
- [ ] TDD cycle verified (RED then GREEN)
- [ ] All existing tests pass
- [ ] "Failing test first" rule in CLAUDE.md
- [ ] Memory file created and indexed
