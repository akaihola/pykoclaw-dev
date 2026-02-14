# Reply Tag Envelope — Suppress Internal Monologue

## TL;DR

> **Quick Summary**: Add `<reply>` tag allowlist to prevent the ambient WhatsApp bot from leaking LLM internal monologue ("I'll silently update...") as chat messages. Only text wrapped in `<reply>` tags gets sent to WhatsApp; everything else is discarded.
> 
> **Deliverables**:
> - Updated system prompt with `<reply>` tag instructions
> - `_extract_reply()` function for tag parsing
> - Updated `_handle_agent_trigger()` to filter through `_extract_reply()`
> - 6 new tests + 1 updated existing test
> 
> **Estimated Effort**: Quick
> **Parallel Execution**: NO — sequential (2 tasks, second depends on first)
> **Critical Path**: Task 1 (connection.py) → Task 2 (tests)

---

## Context

### Original Request
Bot leaks internal reasoning text as WhatsApp messages. Examples:
- "I'll silently update the memory files with this important information..."
- "I'll silently log this to the daily memory file"

### Root Cause
`connection.py:183-201` collects ALL `AgentMessage(type="text")` and sends concatenated result to WhatsApp. System prompt says "produce no text" but LLM narrates tool calls reflexively.

### Design Decision
Allowlist (`<reply>` tags) over denylist (`<thinking>` tags) because:
- Failure mode = silence (safe) vs leakage (unsafe)
- LLMs follow XML tag instructions reliably
- ~10 lines of logic change

---

## Work Objectives

### Core Objective
Make untagged LLM text invisible to WhatsApp users. Only `<reply>`-wrapped content gets sent.

### Definition of Done
- [x] Internal monologue without `<reply>` tags → not sent
- [x] Text inside `<reply>` tags → sent to WhatsApp
- [x] Hard mention prompt reinforces `<reply>` tag usage
- [x] All existing + new tests pass (0 failures)

### Must NOT Have
- Changes to `agent_core.py`, `scheduler.py`, `pykoclaw-chat/`, or any file outside `pykoclaw-whatsapp/`
- Changes to the `AgentMessage` dataclass
- Config option to disable filtering (this is a safety feature, always on)
- Logging of filtered monologue content (may contain sensitive reasoning)
- `<thinking>` tag support (denylist approach rejected)

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES
- **Automated tests**: YES (tests-after, integrated in task)
- **Framework**: pytest + pytest-asyncio

---

## TODOs

- [x] 1. Add `<reply>` tag parsing and system prompt update in `connection.py`

  **What to do**:
  - Add `import re` to imports
  - Add `_extract_reply(text: str) -> str | None` module-level function:
    - Use `re.findall(r'<reply>(.*?)</reply>', text, re.DOTALL)` to extract tagged content
    - Strip whitespace from each match
    - Filter out empty matches
    - Join remaining with `"\n"` 
    - Return joined string if non-empty, else `None`
  - Update `_build_system_prompt()` — add `<reply>` tag instruction BEFORE the behavioral rules (silence/reply criteria). Wording:
    - *"When you choose to reply, wrap your ENTIRE reply in `<reply>` tags. Text outside these tags will NOT be delivered to the chat. Tool-call reasoning and internal notes must NOT be wrapped in `<reply>` tags."*
  - Update hard-mention addendum to reinforce: *"You MUST reply using `<reply>` tags."*
  - Update `_handle_agent_trigger()` lines 198-204: replace direct `full_response` usage with `_extract_reply(full_response)`. Send only if result is not `None`.

  **Must NOT do**:
  - Don't remove any existing behavioral guidance (silence rules, name recognition)
  - Don't log the filtered monologue content
  - Don't touch any file outside `connection.py`

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (first)
  - **Blocks**: Task 2
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:128-156` — `_build_system_prompt()`, uses `dedent()`, this is where `<reply>` instruction goes
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:183-204` — `_handle_agent_trigger()` response collection loop and send logic — replace lines 198-204 with `_extract_reply()` call
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:132` — existing `dedent()` usage pattern to follow

  **Acceptance Criteria**:

  - [x] `import re` present in connection.py
  - [x] `_extract_reply()` function exists and is callable
  - [x] System prompt contains `<reply>` tag instruction
  - [x] Hard-mention prompt contains `<reply>` tag reinforcement
  - [x] `_handle_agent_trigger()` calls `_extract_reply()` before sending

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: System prompt contains reply tag instruction
    Tool: Bash (python)
    Preconditions: pykoclaw-whatsapp installed
    Steps:
      1. uv run python -c "
         from pykoclaw_whatsapp.connection import WhatsAppConnection
         import sqlite3
         db = sqlite3.connect(':memory:')
         conn = WhatsAppConnection.__new__(WhatsAppConnection)
         from pykoclaw_whatsapp.config import WhatsAppSettings
         conn._config = WhatsAppSettings(trigger_name='Andy')
         prompt = conn._build_system_prompt('test@g.us', hard_mention=False)
         assert '<reply>' in prompt, f'Missing <reply> in prompt'
         print('OK')
         "
      2. Assert: stdout contains "OK"
    Expected Result: System prompt includes `<reply>` tag instruction

  Scenario: Hard-mention prompt reinforces reply tags
    Tool: Bash (python)
    Steps:
      1. Same as above but with hard_mention=True
      2. Assert: prompt contains both '<reply>' and 'MUST'
    Expected Result: Hard mention prompt reinforces tag usage

  Scenario: _extract_reply strips untagged text
    Tool: Bash (python)
    Steps:
      1. uv run python -c "
         from pykoclaw_whatsapp.connection import _extract_reply
         assert _extract_reply('I will silently update files') is None
         assert _extract_reply('<reply>Hello!</reply>') == 'Hello!'
         assert _extract_reply('thinking...\n<reply>Hi</reply>\nmore thinking') == 'Hi'
         assert _extract_reply('<reply>   </reply>') is None
         assert _extract_reply('<reply>A</reply> noise <reply>B</reply>') == 'A\nB'
         print('ALL OK')
         "
      2. Assert: stdout contains "ALL OK"
    Expected Result: Tag parsing works for all cases
  ```

  **Commit**: YES
  - Message: `fix(wa): add <reply> tag envelope to prevent internal monologue leakage`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`

---

- [x] 2. Update and add tests in `test_connection.py`

  **What to do**:
  - Update `_fake_agent_text` helper (line 83-87): change yielded text from `"Hello from agent"` to `"<reply>Hello from agent</reply>"`
  - Add `_fake_agent_monologue` helper: yields `AgentMessage(type="text", text="I'll silently update the memory files")` (no tags) + result
  - Add `_fake_agent_tagged_and_monologue` helper: yields `AgentMessage(type="text", text="thinking...\n<reply>Hello!</reply>")` + result
  - Add 6 new test functions:

  | Test | Input | Assert |
  |------|-------|--------|
  | `test_monologue_filtered` | `_fake_agent_monologue` | `send()` NOT called |
  | `test_reply_tags_extracted` | `_fake_agent_tagged_and_monologue` | `send()` called with `"Hello!"` |
  | `test_multiple_reply_tags` | text: `"<reply>Part 1</reply>\nnoise\n<reply>Part 2</reply>"` | `send()` called with `"Part 1\nPart 2"` |
  | `test_whitespace_only_reply_tag` | text: `"<reply>   </reply>"` | `send()` NOT called |
  | `test_reply_with_newlines` | text: `"<reply>Line 1\nLine 2</reply>"` | `send()` called with `"Line 1\nLine 2"` |
  | `test_extract_reply_unit` | Direct unit test of `_extract_reply()` function | Various assertions |

  - Verify ALL existing tests still pass (8 existing, especially `test_reply_sent_with_text` which now depends on the updated `_fake_agent_text`)

  **Must NOT do**:
  - Don't delete or rename existing tests — update them
  - Don't touch test files outside `test_connection.py`

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (second)
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `pykoclaw-whatsapp/tests/test_connection.py:83-100` — existing `_fake_agent_*` async generator helpers — follow this pattern for new helpers
  - `pykoclaw-whatsapp/tests/test_connection.py:174-189` — `test_reply_sent_with_text` — this test MUST be updated (change `_fake_agent_text` to yield `<reply>` tags)
  - `pykoclaw-whatsapp/tests/test_connection.py:140-171` — existing suppression tests — follow this pattern for new suppression tests

  **Acceptance Criteria**:

  - [x] `_fake_agent_text` yields text with `<reply>` tags
  - [x] `_fake_agent_monologue` helper exists (no tags)
  - [x] 6 new test functions exist
  - [x] `uv run python -m pytest pykoclaw-whatsapp/tests/test_connection.py -v` → 14+ tests, 0 failures
  - [x] `uv run python -m pytest pykoclaw-whatsapp/tests/ -v` → 0 failures, 0 errors (no regressions)

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: All connection tests pass
    Tool: Bash
    Preconditions: Task 1 complete
    Steps:
      1. cd /home/agent/pykoclaw && uv run python -m pytest pykoclaw-whatsapp/tests/test_connection.py -v
      2. Assert: exit code 0
      3. Assert: "14 passed" or more in output
      4. Assert: "0 failed" or no "FAILED" in output
    Expected Result: All 14+ tests pass

  Scenario: Full WhatsApp test suite — no regressions
    Tool: Bash
    Steps:
      1. cd /home/agent/pykoclaw && uv run python -m pytest pykoclaw-whatsapp/tests/ -v
      2. Assert: exit code 0
      3. Assert: no "FAILED" in output
    Expected Result: All tests pass (52+ expected)

  Scenario: Linting passes
    Tool: Bash
    Steps:
      1. cd /home/agent/pykoclaw && uv run ruff check pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py pykoclaw-whatsapp/tests/test_connection.py
      2. Assert: exit code 0
    Expected Result: No lint errors
  ```

  **Commit**: YES
  - Message: `test(wa): add reply tag envelope tests and update existing helpers`
  - Files: `pykoclaw-whatsapp/tests/test_connection.py`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `fix(wa): add <reply> tag envelope to prevent internal monologue leakage` | connection.py | QA scenarios |
| 2 | `test(wa): add reply tag envelope tests and update existing helpers` | test_connection.py | pytest full suite |

---

## Success Criteria

### Verification Commands
```bash
# All connection tests pass (14+)
cd /home/agent/pykoclaw && uv run python -m pytest pykoclaw-whatsapp/tests/test_connection.py -v

# Full WhatsApp test suite — no regressions
cd /home/agent/pykoclaw && uv run python -m pytest pykoclaw-whatsapp/tests/ -v

# Lint clean
cd /home/agent/pykoclaw && uv run ruff check pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py pykoclaw-whatsapp/tests/test_connection.py
```

### Final Checklist
- [x] Untagged LLM text is NOT sent to WhatsApp
- [x] `<reply>`-tagged text IS sent to WhatsApp
- [x] Multiple `<reply>` blocks are joined with newline
- [x] Whitespace-only `<reply>` blocks are treated as silence
- [x] Hard mention prompt reinforces `<reply>` tag usage
- [x] All existing tests still pass (no regressions)
- [x] Only `connection.py` and `test_connection.py` modified
