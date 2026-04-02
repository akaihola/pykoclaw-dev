# ACP Attachment Support (JPEG, PDF, Binary Files)

## Status: Backlog
## Priority: 2

## TL;DR

> **Quick Summary**: Add multimodal attachment support to pykoclaw ACP
> conversations. Currently `server.py` silently drops non-text content blocks
> from ACP prompts. Fix this by translating ACP content blocks (image, resource)
> into Anthropic API content blocks and sending them to the Claude Code CLI
> subprocess via the SDK's `AsyncIterable[dict]` path.
>
> **Deliverables**:
> - Attachment utility module in pykoclaw core (`pykoclaw/attachments.py`)
> - Updated ACP server to extract and forward all content block types
> - Updated client pool to send multimodal content via `AsyncIterable`
> - ACP capability advertisement (`promptCapabilities.image: true`)
> - `pykoclaw prompt --attachment` CLI command for debugging
> - Fixed stale ACP tests (4 currently broken)
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES — 2 waves
> **Critical Path**: Task 1 → Task 2 → Task 3 → Tasks 4+5 → Task 6

---

## Context

### Original Request

When attaching JPEGs or PDFs in Mitto in a `pykoclaw acp` conversation, the
agent never sees the attachments. Text file attachments work because Mitto wraps
them as `type: "text"` items with `=== File: ===` blocks. Binary attachments
arrive as different ACP content block types and are silently dropped.

### Confirmed reproduction (2026-03-17)

Investigated via Claude Code session file `a24e771e-2bc3-4e6a-a47e-264e6f6e7496`
(Mitto session `20260314-165042-db914017`) after a user reported the AI ignoring
an attachment. The session JSONL confirmed that the first message received by
Claude Code already had the attachment-bearing Turn 1 as plain-text history —
no image content block ever reached the worker. Mitto logs confirmed
`prompt_failed: peer disconnected before response` (service restart), but even
without that restart, pykoclaw-acp would have dropped the image block here.
The two failure modes are independent and both need fixing.

### Root Cause

`pykoclaw-acp/src/pykoclaw_acp/server.py` lines 129–134:

```python
text_parts = [
    item.get("text", "")
    for item in prompt_items
    if isinstance(item, dict) and item.get("type") == "text"
]
content = "\n".join(text_parts)
```

Only `type == "text"` items are extracted. Everything else is discarded.

### Architecture (ACP Data Path)

```
Mitto → server.py → client_pool.py → ClaudeSDKClient.query() → Claude Code CLI
```

This path does NOT go through `dispatch_to_agent()` or `query_agent()`. The
`pykoclaw-messaging` and `pykoclaw` core `agent_core.py` modules are not in the
ACP data path. Changes are limited to `pykoclaw-acp` and a small utility in
`pykoclaw` core.

### Interview Summary

**Key Discussions**:

- **Where shared code lives**: User decided on `pykoclaw` core (not a separate
  `pykoclaw-attachments` package). Rationale: ~40–50 lines of stdlib-only code
  is too small for a separate package, and core needs it for
  `pykoclaw prompt --attachment`.
- **Multimodal passthrough**: Send images and PDFs as base64 content blocks
  directly to Claude for native multimodal processing. No text extraction, no
  heavy dependencies like `pdfplumber`.
- **SDK capabilities**: `ClaudeSDKClient.query()` accepts
  `str | AsyncIterable[dict[str, Any]]`. The `AsyncIterable` path sends raw
  dicts to the Claude Code CLI — untyped, so we can send standard Anthropic API
  content blocks (image, document). The SDK's `ContentBlock` union has no image
  or document types.
- **Scope boundary**: No changes to `pykoclaw-messaging` or `agent_core.py`'s
  function signature. The CLI debug command uses `ClaudeSDKClient` directly.

**Research Findings**:

- SDK `query()` wraps string prompts as
  `{"type": "user", "message": {"role": "user", "content": prompt}}`.
  `AsyncIterable` path passes dicts through with `session_id` injection.
- ACP spec requires `promptCapabilities.image: true` in `initialize` response
  for clients to send image content. Current code returns empty capabilities.
- ACP `ContentBlock` types: `Text`, `Image`, `Resource`, `ResourceLink`, `Audio`.
  Agent MUST support `Text` and `ResourceLink` as baseline.
- ACP content block format differs from Anthropic API format (different field
  names, nesting structure). Translation is needed.

### Metis Review

**Identified Gaps** (addressed):

- **4 broken tests**: ACP tests patch `dispatch_to_agent` which no longer exists
  in `server.py` (stale from prior refactor to `ClientPool`). Must fix before
  adding new code.
- **ACP → Anthropic format translation**: Different field names (`mimeType` vs
  `media_type`), different nesting (flat vs `source: {}`), different type names
  (`resource` blob → `document`).
- **AsyncIterable envelope**: Must construct full message envelope
  (`{"type": "user", "message": {"role": "user", "content": [...]}}`) and wrap
  in async generator — not just pass a list.
- **Capability advertisement**: Must add `promptCapabilities.image: true` in
  `initialize` response.
- **Content validation**: Must allow image-only prompts (no text required when
  attachments present).
- **Unsupported types**: Must log warnings for `audio`, `resource_link`, unknown
  types — not silently drop them.

---

## Work Objectives

### Core Objective

Enable JPEG, PDF, and other binary attachments to reach the Claude agent in ACP
conversations by translating ACP content blocks into Anthropic API content blocks
and sending them through the SDK's multimodal input path.

### Concrete Deliverables

- `pykoclaw/src/pykoclaw/attachments.py` — ACP→Anthropic content block
  translator (~50–80 lines, stdlib-only)
- `pykoclaw-acp/src/pykoclaw_acp/server.py` — updated `_handle_session_prompt`
  to extract all content types and advertise capabilities
- `pykoclaw-acp/src/pykoclaw_acp/client_pool.py` — updated `send()`/`_query()`
  to accept and forward multimodal content via `AsyncIterable`
- `pykoclaw/src/pykoclaw/__main__.py` — new `pykoclaw prompt` command
- `pykoclaw-acp/tests/test_server.py` — fixed stale tests + new attachment tests
- `pykoclaw/tests/test_attachments.py` — unit tests for content block translator

### Definition of Done

- [ ] `uv run pytest pykoclaw-acp/tests/ -v` — 0 failures (stale tests fixed +
      new tests pass)
- [ ] `uv run pytest pykoclaw/tests/test_attachments.py -v` — all pass
- [ ] `uv run pykoclaw prompt --help` shows `--attachment` option
- [ ] Empirical test confirms Claude Code CLI accepts multimodal content blocks

### Must Have

- Image content blocks (JPEG, PNG, GIF, WebP) forwarded to Claude
- PDF/document content blocks forwarded to Claude
- Text content blocks continue working (regression safety)
- Capability advertisement in `initialize` response
- Warning log for unsupported content types (never silently drop)
- `pykoclaw prompt --attachment` debugging command

### Must NOT Have (Guardrails)

- NO changes to `pykoclaw-messaging/dispatch.py`
- NO changes to `query_agent()` signature in `agent_core.py`
- NO `resource_link` handling (requires file I/O, path traversal safety — separate feature)
- NO `audio` handling (not supported by Claude vision API)
- NO URL-based image sources (Anthropic `source.type: "url"` — ACP sends inline data)
- NO text extraction from PDFs (use Claude's native document understanding)
- NO image parsing/dimension validation (just MIME detection + base64 passthrough)
- NO new package/repository — all code in existing packages
- NO streaming of large attachments — in-memory encoding with size limit

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks are verifiable WITHOUT any human action.

### Test Decision

- **Infrastructure exists**: YES (`pytest` + `pytest-asyncio`)
- **Automated tests**: YES (tests-after — fix broken tests first, then add new
  tests alongside implementation)
- **Framework**: `pytest` (+ `pytest-asyncio` for async tests)

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

Every task includes specific QA scenarios the executing agent runs directly.
No "user manually tests via Mitto" criteria.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Fix broken ACP tests (establish mock pattern)
└── Task 2: Empirical SDK multimodal verification (go/no-go gate)

Wave 2 (After Wave 1):
└── Task 3: Attachment utility module in pykoclaw core

Wave 3 (After Task 3):
├── Task 4: ACP server.py changes (content extraction + capabilities)
└── Task 5: ACP client_pool.py changes (AsyncIterable wrapping)

Wave 4 (After Wave 3):
└── Task 6: `pykoclaw prompt --attachment` CLI command

Critical Path: Task 1 → Task 3 → Task 4 → Task 6
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 3, 4, 5 | 2 |
| 2 | None | 3 (go/no-go) | 1 |
| 3 | 1, 2 | 4, 5, 6 | None |
| 4 | 3 | 6 | 5 |
| 5 | 3 | 6 | 4 |
| 6 | 4, 5 | None | None (final) |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 2 | Two parallel `quick` tasks |
| 2 | 3 | Single `unspecified-low` task |
| 3 | 4, 5 | Two parallel `unspecified-low` tasks |
| 4 | 6 | Single `unspecified-low` task |

---

## TODOs

- [ ] 1. Fix 4 broken ACP tests

  **What to do**:
  - The 4 failing tests in `pykoclaw-acp/tests/test_server.py` all patch
    `pykoclaw_acp.server.dispatch_to_agent`, which no longer exists. The server
    was refactored to use `ClientPool.send()` instead.
  - Fix each test to mock `ClientPool.send()` (on the `self._pool` instance)
    instead of the removed `dispatch_to_agent` function.
  - The 4 tests to fix:
    - `test_session_prompt_streams_via_dispatch` (line 124)
    - `test_session_prompt_dispatch_error_sends_notification` (line 168)
    - `test_session_prompt_dispatch_error_server_survives` (line 205)
    - `test_dispatch_error_does_not_catch_cancelled_error` (line 273)
  - Each test currently does
    `with patch("pykoclaw_acp.server.dispatch_to_agent", mock_dispatch)`.
    Change to patch `server._pool.send` as an `AsyncMock`.
  - Adjust assertions: `dispatch_to_agent` was called with kwargs
    (`prompt=`, `channel_prefix=`, `channel_id=`, `on_text=`). `pool.send()`
    is called with positional `session_id`, `prompt`, and kwarg `on_text=`.
    Update `assert_awaited_once` checks and `call_args` assertions accordingly.
  - The test `test_session_prompt_streams_via_dispatch` checks for an
    "acknowledgment" response (`written[1]` with `result == {}`), but
    current `server.py` sends the prompt response AFTER streaming with
    `{"stopReason": "end_turn"}`. Update the assertion to match actual behavior.
  - Rename tests to remove `dispatch` from their names (they test `pool.send`
    now).

  **Must NOT do**:
  - Do NOT change any behavior in `server.py` or `client_pool.py` — only fix
    the tests.
  - Do NOT add attachment-related tests yet — that's later tasks.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Tasks 3, 4, 5
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `pykoclaw-acp/tests/test_server.py:38-48` — `_collect_writes()` helper that
    captures JSON-RPC output from the server. All tests use this pattern.
  - `pykoclaw-acp/tests/test_server.py:52-61` — `test_initialize` as an example
    of a working test that doesn't need fixing.
  - `pykoclaw-acp/tests/test_server.py:242-270` —
    `test_main_loop_continues_after_dispatch_error` — a currently-passing test
    that patches `server._dispatch` directly instead of `dispatch_to_agent`.
    Shows the alternative mock approach.

  **API References**:
  - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:75-96` — `ClientPool.send()`
    signature: `send(self, session_id: str, prompt: str, *, on_text=None)`.
    This is what the mock must target.
  - `pykoclaw-acp/src/pykoclaw_acp/server.py:115-179` —
    `_handle_session_prompt()` — the method under test. Shows how `self._pool`
    is used: `await self._pool.send(session_id, content, on_text=_send_chunk)`.

  **Acceptance Criteria**:
  - [ ] `uv run pytest pykoclaw-acp/tests/ -v` → 0 failures, 0 errors
  - [ ] All 4 previously-failing tests now pass
  - [ ] No test patches `dispatch_to_agent` anywhere
  - [ ] All 23 previously-passing tests still pass (regression)

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: All ACP tests pass after fix
    Tool: Bash
    Preconditions: uv sync completed
    Steps:
      1. Run: uv run pytest pykoclaw-acp/tests/ -v
      2. Assert: exit code is 0
      3. Assert: output contains "passed" and does NOT contain "FAILED"
      4. Assert: output shows all 4 fixed tests as PASSED
    Expected Result: 0 failures across all tests
    Evidence: Terminal output captured
  ```

  ```
  Scenario: No stale dispatch_to_agent references remain in tests
    Tool: Bash
    Preconditions: None
    Steps:
      1. Run: grep -r "dispatch_to_agent" pykoclaw-acp/tests/
      2. Assert: exit code is 1 (no matches found)
    Expected Result: Zero occurrences of dispatch_to_agent in test files
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `fix(acp): update stale tests to mock ClientPool.send instead of removed dispatch_to_agent`
  - Files: `pykoclaw-acp/tests/test_server.py`
  - Pre-commit: `uv run pytest pykoclaw-acp/tests/ -v`

---

- [ ] 2. Empirical verification: Claude Code CLI accepts multimodal content blocks

  **What to do**:
  - Write a throwaway test script that sends a small image through
    `ClaudeSDKClient.query()` using the `AsyncIterable[dict]` path and checks
    whether Claude responds with image understanding (not an error).
  - Create a minimal test image (a 1×1 red pixel JPEG, or a small PNG) as
    inline base64 in the script.
  - Construct the full message envelope:
    ```python
    message = {
        "type": "user",
        "message": {
            "role": "user",
            "content": [
                {"type": "text", "text": "What color is this image? Reply with just the color."},
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/png",
                        "data": "<base64 of small test image>",
                    },
                },
            ],
        },
        "parent_tool_use_id": None,
    }
    ```
  - Wrap in an async generator and pass to `client.query()`.
  - Receive response via `client.receive_response()`.
  - Check: does the response contain a `TextBlock` with a color-related word?
    Or does it error out?
  - Also test with a small PDF (a minimal valid PDF with "Hello World" text):
    ```python
    {"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": "..."}}
    ```
  - Place the script in `scripts/test_multimodal_sdk.py` (PEP 723 inline
    metadata with `claude-agent-sdk` dependency).
  - This is a **go/no-go gate**. If this fails:
    - The fallback approach is: save attachments to the conversation directory as
      files, mention them in the text prompt so the agent can use `Read` to
      access text-based files. Images would require a different strategy.
    - Do NOT proceed with Tasks 3–6 as written. Re-plan.

  **Must NOT do**:
  - Do NOT commit this script to the repo permanently — it's a throwaway
    verification.
  - Do NOT use the Anthropic API directly — test through `ClaudeSDKClient` to
    verify the SDK→CLI→model path.

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 3 (go/no-go gate)
  - **Blocked By**: None

  **References**:

  **API References**:
  - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:131-146` — shows how to
    construct `ClaudeAgentOptions` and create/connect a `ClaudeSDKClient`. Copy
    this pattern for the test script.
  - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:98-117` — shows how to call
    `client.query()` and iterate `client.receive_response()`. The test script
    follows this pattern.

  **SDK References**:
  - `ClaudeSDKClient.query()` source (inspected during interview) — shows the
    `AsyncIterable` path writes each dict as JSON + newline to transport.
    The dict must include `"type": "user"` and `"message"` with `"role"` and
    `"content"` fields.

  **External References**:
  - Anthropic API docs for image content blocks:
    `https://docs.anthropic.com/en/docs/build-with-claude/vision`
  - Anthropic API docs for PDF content blocks:
    `https://docs.anthropic.com/en/docs/build-with-claude/pdf-support`

  **Acceptance Criteria**:
  - [ ] Script runs without crashing: `uv run scripts/test_multimodal_sdk.py`
  - [ ] Image test: Claude responds with a text message (not an error)
  - [ ] PDF test: Claude responds with text referencing the PDF content
  - [ ] Script prints clear PASS/FAIL verdict for each test

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Multimodal image input via SDK AsyncIterable path
    Tool: Bash
    Preconditions: ANTHROPIC_API_KEY set, ClaudeSDKClient available
    Steps:
      1. Run: uv run scripts/test_multimodal_sdk.py
      2. Wait for output (timeout: 60s)
      3. Assert: output contains "IMAGE: PASS" or similar success indicator
      4. Assert: output contains "PDF: PASS" or similar success indicator
      5. Assert: exit code is 0
    Expected Result: Both image and PDF multimodal inputs accepted by CLI
    Evidence: Terminal output captured

  Scenario: Fallback needed (if test fails)
    Tool: Bash
    Preconditions: Previous scenario FAILED
    Steps:
      1. Capture the error output
      2. Determine failure mode: SDK error? CLI rejection? Model error?
      3. Document findings for re-planning
    Expected Result: Clear diagnosis of why multimodal path fails
    Evidence: Error output captured
  ```

  **Commit**: NO (throwaway script)

---

- [ ] 3. Attachment utility module in pykoclaw core

  **What to do**:
  - Create `pykoclaw/src/pykoclaw/attachments.py` — a pure-function module that
    translates ACP content blocks into Anthropic API content blocks.
  - Use ONLY stdlib: `mimetypes`, `base64`, `pathlib`, `logging`.
  - The module provides two public functions:

    **Function 1: `acp_parts_to_anthropic_blocks`**
    ```python
    def acp_parts_to_anthropic_blocks(
        items: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
    ```
    Takes a list of ACP `ContentBlock` dicts from a `session/prompt` request.
    Returns a list of Anthropic API content block dicts. Handles:

    | ACP type | ACP structure | Anthropic output |
    |----------|--------------|-----------------|
    | `text` | `{"type": "text", "text": "..."}` | `{"type": "text", "text": "..."}` (passthrough) |
    | `image` | `{"type": "image", "data": "...", "mimeType": "image/png"}` | `{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "..."}}` |
    | `resource` (blob) | `{"type": "resource", "resource": {"blob": "...", "mimeType": "application/pdf"}}` | `{"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": "..."}}` |
    | `resource` (text) | `{"type": "resource", "resource": {"text": "...", "mimeType": "text/plain"}}` | `{"type": "text", "text": "..."}` (with filename context if available) |
    | `resource_link` | any | Log warning, skip |
    | `audio` | any | Log warning, skip |
    | unknown | any | Log warning, skip |

    For `resource` with blob: detect whether the MIME type is an image type
    (`image/*`) or a document type (`application/pdf`) and produce the
    appropriate Anthropic block type.

    **Function 2: `files_to_anthropic_blocks`**
    ```python
    def files_to_anthropic_blocks(
        paths: list[Path],
    ) -> list[dict[str, Any]]:
    ```
    Takes a list of file paths (from `pykoclaw prompt --attachment`). Reads each
    file, detects MIME type via `mimetypes.guess_type()`, base64-encodes, and
    returns Anthropic content blocks. This function does the file I/O that
    `acp_parts_to_anthropic_blocks` doesn't need (ACP sends inline data).

    Size limit: reject files > 20 MB with a `ValueError`.

  - Create `pykoclaw/tests/test_attachments.py` with unit tests covering:
    - Text passthrough (regression)
    - Image block translation (ACP → Anthropic)
    - Resource blob with PDF MIME → document block
    - Resource blob with image MIME → image block
    - Resource text → text block
    - Mixed content (text + image + resource)
    - Image-only (no text) → returns list with only image block
    - Unknown type → returns empty list + logs warning
    - Audio type → returns empty list + logs warning
    - `resource_link` → returns empty list + logs warning
    - `files_to_anthropic_blocks`: reads file, detects MIME, returns correct
      block type
    - `files_to_anthropic_blocks`: rejects file > 20 MB with ValueError

  **Must NOT do**:
  - Do NOT add any non-stdlib dependencies.
  - Do NOT do image parsing, dimension validation, or format conversion.
  - Do NOT handle `resource_link` (log and skip).
  - Do NOT handle `audio` (log and skip).
  - Do NOT fetch URLs.
  - Do NOT stream files — read entirely into memory (size limit protects).

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 2 (sequential)
  - **Blocks**: Tasks 4, 5, 6
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - `pykoclaw/src/pykoclaw/tools.py` — example of a utility module in core.
    Follow the same style: module docstring, type hints on all signatures,
    `log = logging.getLogger(__name__)`.
  - `pykoclaw/src/pykoclaw/models.py` — example of a simple module in core.

  **External References**:
  - Anthropic API image content block:
    `{"type": "image", "source": {"type": "base64", "media_type": "...", "data": "..."}}`
  - Anthropic API document content block:
    `{"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": "..."}}`
  - ACP schema `ContentBlock` type definition:
    `https://agentclientprotocol.com/protocol/schema` — see `ContentBlock` union
    type for exact field names. **The executor MUST verify the exact ACP field
    names from this spec before implementing.** The interview identified
    `mimeType` and `data` for images, and `resource.blob`/`resource.text` for
    resources, but this must be confirmed against the spec.

  **Test References**:
  - `pykoclaw/tests/` — existing test directory. Place new tests here as
    `test_attachments.py`.

  **Acceptance Criteria**:
  - [ ] `pykoclaw/src/pykoclaw/attachments.py` exists with both public functions
  - [ ] `uv run pytest pykoclaw/tests/test_attachments.py -v` → all pass
  - [ ] All test cases listed above are covered
  - [ ] Module uses only stdlib imports
  - [ ] All functions have type hints
  - [ ] Unknown/unsupported types log warnings (verify with `caplog` fixture)

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Unit tests pass for attachment utility
    Tool: Bash
    Preconditions: uv sync completed
    Steps:
      1. Run: uv run pytest pykoclaw/tests/test_attachments.py -v
      2. Assert: exit code is 0
      3. Assert: output shows all test cases as PASSED
      4. Assert: no warnings about missing test cases
    Expected Result: All unit tests pass
    Evidence: Terminal output captured
  ```

  ```
  Scenario: Module has no non-stdlib dependencies
    Tool: Bash
    Preconditions: Module exists
    Steps:
      1. Run: grep "^import\|^from" pykoclaw/src/pykoclaw/attachments.py
      2. Assert: all imports are from stdlib (base64, mimetypes, pathlib,
         logging, typing, collections.abc) or from __future__
      3. Assert: no third-party imports
    Expected Result: Only stdlib imports present
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `feat(core): add attachment utility for ACP-to-Anthropic content block translation`
  - Files: `pykoclaw/src/pykoclaw/attachments.py`,
    `pykoclaw/tests/test_attachments.py`
  - Pre-commit: `uv run pytest pykoclaw/tests/test_attachments.py -v`

---

- [ ] 4. Update ACP server.py: content extraction + capability advertisement

  **What to do**:

  **4a. Capability advertisement** (in `_handle_initialize`):
  - Update `server.py:101-105` to advertise image support:
    ```python
    "agentCapabilities": {
        "promptCapabilities": {
            "image": True,
        },
    },
    ```
  - This tells ACP clients (Mitto) that pykoclaw can handle image content
    blocks.

  **4b. Content extraction** (in `_handle_session_prompt`):
  - Replace the text-only filter (lines 129–134) with a call to
    `acp_parts_to_anthropic_blocks()` from `pykoclaw.attachments`.
  - The result is a `list[dict]` of Anthropic content blocks.
  - If the result is empty (all items were unsupported types), return
    `INVALID_PARAMS` error (same as current empty-prompt behavior).
  - If the result contains only text blocks, extract text and pass as `str`
    to `self._pool.send()` (preserving current behavior for text-only prompts).
  - If the result contains any non-text blocks (image, document), pass the
    full list of content blocks to `self._pool.send()` (requires the new
    signature from Task 5).

  **4c. Update content validation** (lines 136–144):
  - Current code rejects prompts where text content is empty. After this
    change, an image-only prompt (no text) is valid.
  - Change validation to: reject if `acp_parts_to_anthropic_blocks()` returns
    an empty list.

  **4d. Add tests**:
  - Test: `initialize` response includes `promptCapabilities.image: true`
  - Test: prompt with `type: "image"` item → `pool.send()` called with
    list containing Anthropic image block
  - Test: prompt with `type: "text"` only → `pool.send()` called with `str`
    (backward compatibility)
  - Test: prompt with mixed text + image → `pool.send()` called with list
    containing both block types
  - Test: prompt with only unsupported types → `INVALID_PARAMS` error
  - Test: prompt with image-only (no text) → `pool.send()` called (not
    rejected)

  **Must NOT do**:
  - Do NOT change `client_pool.py` in this task — that's Task 5.
  - Do NOT change the JSON-RPC protocol or add new methods.
  - Do NOT handle `resource_link` or `audio` (the utility already skips them).

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 5)
  - **Blocks**: Task 6
  - **Blocked By**: Task 3

  **References**:

  **Pattern References**:
  - `pykoclaw-acp/src/pykoclaw_acp/server.py:100-106` —
    `_handle_initialize()` where capability advertisement goes.
  - `pykoclaw-acp/src/pykoclaw_acp/server.py:115-179` —
    `_handle_session_prompt()` — the main method to modify.
  - `pykoclaw-acp/src/pykoclaw_acp/server.py:129-134` — the text-only filter
    to replace.

  **API References**:
  - `pykoclaw/src/pykoclaw/attachments.py:acp_parts_to_anthropic_blocks()` —
    the function to call (from Task 3).
  - ACP `agentCapabilities` default:
    `{"promptCapabilities": {"audio": false, "embeddedContext": false, "image": false}}`.
    Set `image: true`.

  **Test References**:
  - `pykoclaw-acp/tests/test_server.py:52-61` — `test_initialize` — existing
    test that checks `initialize` response. Add capability assertion here or
    in a new test.
  - `pykoclaw-acp/tests/test_server.py:38-48` — `_collect_writes()` helper.

  **Acceptance Criteria**:
  - [ ] `initialize` response contains `promptCapabilities.image: true`
  - [ ] Image prompt items reach `pool.send()` as Anthropic content blocks
  - [ ] Text-only prompts still pass as `str` to `pool.send()` (regression)
  - [ ] Image-only prompts (no text) are accepted (not rejected)
  - [ ] Unsupported-type-only prompts return `INVALID_PARAMS`
  - [ ] `uv run pytest pykoclaw-acp/tests/ -v` → 0 failures

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: All ACP tests pass including new attachment tests
    Tool: Bash
    Preconditions: Tasks 1 and 3 completed
    Steps:
      1. Run: uv run pytest pykoclaw-acp/tests/ -v
      2. Assert: exit code is 0
      3. Assert: output contains new test names (e.g., test_image_prompt,
         test_capability_advertisement)
      4. Assert: no FAILED tests
    Expected Result: All tests pass
    Evidence: Terminal output captured
  ```

  ```
  Scenario: Capability advertisement in initialize response
    Tool: Bash
    Preconditions: Server code updated
    Steps:
      1. Run: echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' |
         timeout 5 uv run pykoclaw acp 2>/dev/null
      2. Parse JSON response
      3. Assert: result.agentCapabilities.promptCapabilities.image is true
    Expected Result: Image capability advertised
    Evidence: Response JSON captured
  ```

  **Commit**: YES
  - Message: `feat(acp): extract all content block types from prompts and advertise image capability`
  - Files: `pykoclaw-acp/src/pykoclaw_acp/server.py`,
    `pykoclaw-acp/tests/test_server.py`
  - Pre-commit: `uv run pytest pykoclaw-acp/tests/ -v`

---

- [ ] 5. Update ACP client_pool.py: AsyncIterable wrapping for multimodal content

  **What to do**:

  **5a. Widen `send()` signature**:
  - Change `prompt: str` to `prompt: str | list[dict[str, Any]]` in
    `send()` (line 78) and `_query()` (line 98).

  **5b. Update `_query()` to handle multimodal content**:
  - When `prompt` is a `str`, call `client.query(prompt)` as before (no change).
  - When `prompt` is a `list[dict]` (content blocks), construct the full
    message envelope and wrap in an async generator:
    ```python
    async def _content_stream(
        content: list[dict[str, Any]],
    ) -> AsyncGenerator[dict[str, Any], None]:
        yield {
            "type": "user",
            "message": {"role": "user", "content": content},
            "parent_tool_use_id": None,
        }
    ```
    Then call `await entry.client.query(_content_stream(prompt))`.
  - The SDK's `query()` method adds `session_id` to each dict if not present,
    so we don't need to include it.

  **5c. Add tests**:
  - Test: `send()` with `str` prompt → `client.query()` called with string
    (backward compatibility)
  - Test: `send()` with `list[dict]` prompt → `client.query()` called with
    an async iterable, and the yielded message has the correct envelope
    structure

  **Must NOT do**:
  - Do NOT change `server.py` in this task — that's Task 4.
  - Do NOT add any new dependencies.
  - Do NOT change the retry/reconnect logic — just widen the type.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Task 4)
  - **Blocks**: Task 6
  - **Blocked By**: Task 3

  **References**:

  **Pattern References**:
  - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:75-96` — `send()` method.
    Widen `prompt` parameter type.
  - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:98-117` — `_query()` method.
    Add branch for `list[dict]` prompt type.

  **SDK References**:
  - `ClaudeSDKClient.query()` source (inspected during interview):
    `async def query(self, prompt: str | AsyncIterable[dict[str, Any]], ...)`.
    When `prompt` is `AsyncIterable`, it iterates and writes each dict as JSON.
    It injects `session_id` into each dict if not present.
  - The message envelope format (from SDK source):
    `{"type": "user", "message": {"role": "user", "content": ...}, "parent_tool_use_id": None}`.

  **Acceptance Criteria**:
  - [ ] `send()` accepts both `str` and `list[dict]` without error
  - [ ] String prompts still work identically (regression)
  - [ ] List prompts are wrapped in async generator with correct envelope
  - [ ] `uv run pytest pykoclaw-acp/tests/ -v` → 0 failures
  - [ ] Type hints are correct (`str | list[dict[str, Any]]`)

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: All ACP tests pass after client_pool changes
    Tool: Bash
    Preconditions: Tasks 1 and 3 completed
    Steps:
      1. Run: uv run pytest pykoclaw-acp/tests/ -v
      2. Assert: exit code is 0
      3. Assert: no FAILED tests
    Expected Result: All tests pass including new client_pool tests
    Evidence: Terminal output captured
  ```

  **Commit**: YES (group with Task 4 if both complete together)
  - Message: `feat(acp): support multimodal content blocks in client pool via AsyncIterable`
  - Files: `pykoclaw-acp/src/pykoclaw_acp/client_pool.py`,
    `pykoclaw-acp/tests/test_client_pool.py` (if new test file created)
  - Pre-commit: `uv run pytest pykoclaw-acp/tests/ -v`

---

- [ ] 6. Add `pykoclaw prompt --attachment` CLI command

  **What to do**:
  - Add a `prompt` subcommand to the core CLI in
    `pykoclaw/src/pykoclaw/__main__.py`.
  - Signature:
    ```
    pykoclaw prompt [--attachment PATH]... [--conversation NAME] PROMPT_WORDS...
    ```
  - `--attachment` / `-a`: repeatable option, each specifying a file path.
  - `--conversation` / `-c`: optional conversation name (default:
    `"prompt-debug"`).
  - `PROMPT_WORDS`: remaining arguments joined with spaces as the text prompt.
  - Implementation:
    1. Read attachment files using `files_to_anthropic_blocks()` from
       `pykoclaw.attachments`.
    2. Build content blocks: text block from prompt words + attachment blocks.
    3. Create `ClaudeSDKClient` directly (like `client_pool.py` does) — do NOT
       use `query_agent()` or `dispatch_to_agent()`.
    4. If content is text-only, use `client.query(text)`.
    5. If content has attachments, wrap in async generator and use
       `client.query(stream)`.
    6. Print response text blocks to stdout as they arrive.
    7. Save conversation session for resumption.
  - This command is primarily for debugging attachment support. Keep it simple.

  **Must NOT do**:
  - Do NOT widen `query_agent()` or `dispatch_to_agent()` signatures.
  - Do NOT add streaming/progress UI — just print text blocks.
  - Do NOT add image display in terminal.
  - Do NOT make this a full-featured chat replacement (that's `pykoclaw chat`).

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (sequential, final task)
  - **Blocks**: None (final)
  - **Blocked By**: Tasks 4, 5

  **References**:

  **Pattern References**:
  - `pykoclaw/src/pykoclaw/__main__.py:46-50` — `scheduler` command
    registration pattern. Follow this for the `prompt` command. Uses
    `@main.command()` decorator and `asyncio.run()` for async work.
  - `pykoclaw/src/pykoclaw/__main__.py:12-13` — `_get_db_and_data_dir()`
    helper. Use this for DB and data dir access.
  - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:131-146` — shows how to
    construct `ClaudeAgentOptions` and create/connect a `ClaudeSDKClient`.
    Copy this pattern.
  - `pykoclaw-acp/src/pykoclaw_acp/client_pool.py:98-117` — shows how to
    iterate `client.receive_response()` and extract `TextBlock` content.

  **API References**:
  - `pykoclaw/src/pykoclaw/attachments.py:files_to_anthropic_blocks()` — the
    function to call for reading files (from Task 3).
  - `claude_agent_sdk.ClaudeSDKClient` — connect, query, receive_response,
    disconnect.
  - `claude_agent_sdk.ClaudeAgentOptions` — cwd, permission_mode, model, etc.

  **Acceptance Criteria**:
  - [ ] `uv run pykoclaw prompt --help` shows `--attachment` and
        `--conversation` options
  - [ ] `uv run pykoclaw prompt "hello"` sends text-only prompt and prints
        response
  - [ ] `uv run pykoclaw prompt -a image.jpg "describe this"` sends multimodal
        prompt
  - [ ] Missing attachment file → clear error message, non-zero exit
  - [ ] Attachment > 20 MB → clear error message, non-zero exit

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Help text shows attachment option
    Tool: Bash
    Preconditions: Code implemented
    Steps:
      1. Run: uv run pykoclaw prompt --help
      2. Assert: output contains "--attachment" or "-a"
      3. Assert: output contains "--conversation" or "-c"
      4. Assert: output contains "PROMPT_WORDS" or similar argument description
    Expected Result: Help text shows all expected options
    Evidence: Terminal output captured
  ```

  ```
  Scenario: Missing attachment file produces clear error
    Tool: Bash
    Preconditions: Code implemented
    Steps:
      1. Run: uv run pykoclaw prompt -a /nonexistent/file.jpg "test"
      2. Assert: exit code is non-zero
      3. Assert: output contains error message mentioning the file path
    Expected Result: Clear error, non-zero exit
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `feat(core): add pykoclaw prompt command with --attachment for debugging multimodal input`
  - Files: `pykoclaw/src/pykoclaw/__main__.py`
  - Pre-commit: `uv run pykoclaw prompt --help`

---

## Commit Strategy

| After Task | Repo | Message | Verification |
|------------|------|---------|--------------|
| 1 | `pykoclaw-acp` | `fix(acp): update stale tests to mock ClientPool.send` | `uv run pytest pykoclaw-acp/tests/ -v` |
| 3 | `pykoclaw` | `feat(core): add attachment utility for content block translation` | `uv run pytest pykoclaw/tests/test_attachments.py -v` |
| 4 | `pykoclaw-acp` | `feat(acp): extract all content types and advertise image capability` | `uv run pytest pykoclaw-acp/tests/ -v` |
| 5 | `pykoclaw-acp` | `feat(acp): support multimodal content in client pool` | `uv run pytest pykoclaw-acp/tests/ -v` |
| 6 | `pykoclaw` | `feat(core): add pykoclaw prompt --attachment command` | `uv run pykoclaw prompt --help` |

Note: Tasks 4 and 5 may be combined into a single commit if done together.

---

## Success Criteria

### Verification Commands

```bash
# All tests pass
uv run pytest pykoclaw-acp/tests/ -v   # Expected: 0 failures
uv run pytest pykoclaw/tests/test_attachments.py -v  # Expected: 0 failures

# CLI command exists
uv run pykoclaw prompt --help  # Expected: shows --attachment option

# Capability advertisement works
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | \
  timeout 5 uv run pykoclaw acp 2>/dev/null | \
  python3 -c "import sys,json; r=json.loads(input()); print(r['result']['agentCapabilities'])"
# Expected: {"promptCapabilities": {"image": true}}
```

### Final Checklist

- [ ] All "Must Have" items present
- [ ] All "Must NOT Have" items absent
- [ ] All tests pass (0 failures across both packages)
- [ ] No `dispatch_to_agent` references in test files
- [ ] Attachment utility has only stdlib imports
- [ ] Multimodal SDK path verified empirically (Task 2)
