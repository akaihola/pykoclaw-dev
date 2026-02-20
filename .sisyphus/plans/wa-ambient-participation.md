# WhatsApp Ambient Participation Mode

## Status: Done

## TL;DR

> **Quick Summary**: Transform pykoclaw-whatsapp from a reactive `@mention`-triggered bot into an ambient participant that silently observes all messages in 90-second batches, lets the LLM decide whether to reply, and can run tool calls (memory, notes) without sending a WhatsApp message.
> 
> **Deliverables**:
> - `BatchAccumulator` class with per-chat timers and hard-mention flush
> - Reworked `MessageHandler.on_message` → batch-based flow replacing `should_trigger()`
> - Reworked `_handle_agent_trigger` → session resumption + conditional reply suppression + ambient system prompt
> - `batch_window_seconds` config setting (default 90)
> - Comprehensive pytest test suite for all new logic
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 2 waves
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 → Task 5

---

## Context

### Original Request
The user wants pykoclaw-whatsapp to observe all messages — not just `@Andy` mentions — and allow the LLM to run tool calls silently (e.g., updating memory/notes) without sending a WhatsApp reply. The LLM itself should decide whether to reply, with `@Andy` as a hard override forcing a reply. Messages should be batched in a 90-second window to manage cost and provide natural interjection delay.

### Interview Summary
**Key Discussions**:
- **Batching**: 90-second configurable debounce. All messages accumulate per-chat, then sent as a single batch to the agent.
- **Hard mention**: `@Andy` (exact `@` + trigger_name, case-insensitive) flushes the batch immediately and forces a reply.
- **LLM-driven trigger**: Instead of string matching name variations (`Andy`, `andy`, `andy:`, inflected forms like "matilta" for "Matti"), the LLM judges whether it's being addressed. This handles any language/inflection.
- **Proactive interjection**: Agent can interject on misinformation/crucial gaps, but natural batch delay (~90-180s) gives humans time to self-correct. No explicit delay mechanism.
- **Shared session**: Same conversation/session for observation and replies. Session context grows over time; agent uses Write tool for long-term persistence.
- **All chats**: No per-chat whitelist. Observation applies everywhere.
- **Tests**: pytest already exists in the project. Add tests for new batch/trigger/suppression logic.

**Research Findings**:
- `store_message()` already persists ALL messages unconditionally — no change needed there.
- `should_trigger()` is simple string matching — will be replaced by batch accumulator + LLM judgment.
- `get_new_messages_for_chat()` uses `last_agent_timestamp` cursor — already supports "messages since last agent run" semantics.
- **Critical gap**: `_handle_agent_trigger()` does NOT use `resume_session_id`. Every invocation creates a new session. Must be fixed (follow `scheduler.py:22-24` pattern).
- **Critical gap**: The `send_message` MCP tool (`__init__.py:102-120`) only writes to DB — it does NOT actually send via WhatsApp. The real send path is `OutgoingQueue.send()`. The agent's text response (via `response_parts`) is what triggers actual WhatsApp delivery.
- Test infrastructure already exists: `pytest` in dev deps, `test_handler.py`, `test_queue.py`, `test_whatsapp_plugin.py` with in-memory DB fixtures.

### Metis Review
**Identified Gaps** (addressed):
- **Session resumption missing**: `_handle_agent_trigger()` never passes `resume_session_id` → Fixed in Task 3.
- **Thread safety for batch accumulator**: Go thread callbacks must bridge to asyncio loop → Use `asyncio.run_coroutine_threadsafe()` pattern.
- **Concurrent agent calls per chat**: Multiple batch flushes for same chat could race → Add per-chat `asyncio.Lock`.
- **`is_from_me` messages re-triggering**: Bot's own messages should NOT start/extend batch timers → Filter in `on_message`.
- **Timer cancellation on hard mention**: Pending batch timer must be cancelled when hard mention flushes → Track timer handles per chat.
- **Empty batch on flush**: Timer fires but messages already processed by earlier hard-mention flush → Skip invocation if `get_new_messages_for_chat()` returns empty.
- **Self-chat behavior**: Self-chat should continue to trigger immediately (bypass batch), same as current behavior.

### External Research Findings

Research into existing ambient chat agent projects (cloneme, wa_llm, CoChat, OpenClaw, LlamaBot) and academic work revealed key lessons:

**Validated design decisions** (our plan already covers these):
- Batching/debounce is the standard approach for cost management ✓
- Per-chat locks preventing concurrent agent calls are essential ✓
- `is_from_me` filtering to prevent feedback loops is critical ✓

**New insights to incorporate**:
1. **Over-responding is the #1 user complaint** with ambient agents. The system prompt must strongly bias toward silence. Research suggests a "participation threshold" — e.g., the agent should contribute to <30% of messages in a group chat. Our system prompt should include explicit guidance: "In group conversations, err heavily toward silence. Most batches should result in no reply."
2. **Processing guard / message deduplication**: `wa_llm` uses a TTL cache (`TTLCache(maxsize=1000, ttl=4*60)`) to prevent duplicate message processing. Our `BatchAccumulator` handles this via its timer mechanism, but we should ensure that if `on_message` is called multiple times for the same message (e.g., due to Neonize's Go threading), we don't create duplicate batch entries. Add a `message_id` dedup set.
3. **Two-stage architecture** (classifier → generator) is common but we're folding both into a single LLM call via the system prompt. This is simpler and fine for our use case, but the insight is that the system prompt must clearly separate the "should I respond?" decision from the "what should I say?" generation.
4. **Session rotation is essential** at ~200 turns or 24 hours. Average WhatsApp message is 15-25 tokens; at 90-second batches with ~10 messages each, that's ~150-250 tokens per batch. After 200 batches (~5 hours of active chat), session context grows to ~17K tokens where accuracy degrades. This is noted as future work but the timeframe is sooner than expected.
5. **cloneme project** (`vibheksoni/cloneme`) implements a full `Decision` class with LLM-driven `should_reply()`, participation rate tracking, information value assessment, and decision caching with TTLs. This is the most sophisticated open-source implementation of what we're building. Key pattern: it separates security analysis, content classification, and information value assessment into cached sub-decisions.

**Anti-patterns to avoid** (from production experience):
- Don't make silence a failure mode — silent execution should be explicit and logged
- Don't volunteer unsolicited opinions or subjective comments
- Users notice when agent responses feel scripted rather than contextual
- Rapid repeated responses are deeply annoying — track recent response timestamps

**Reference projects**:
- `vibheksoni/cloneme` — Most sophisticated LLM-driven reply decision system (Discord)
- `ilanbenb/wa_llm` — WhatsApp LLM bot with TTL-based dedup and group management
- `joysatisficer/chapter2` — Discord bot with `should_reply()` logic and mute controls
- CoChat memory architecture — 3-layer memory with privacy isolation

---

## Work Objectives

### Core Objective
Replace the reactive `@mention` trigger model with a batch-based ambient observation model where ALL messages are accumulated in 90-second windows, sent to the LLM as context, and the LLM decides whether to reply, use tools silently, or do nothing.

### Concrete Deliverables
- New `BatchAccumulator` class in `pykoclaw_whatsapp/handler.py`
- Modified `MessageHandler.on_message` using batch accumulator
- Modified `WhatsAppConnection._handle_agent_trigger` with session resumption + reply suppression
- Updated `WhatsAppSettings` with `batch_window_seconds`
- Ambient participant system prompt
- Comprehensive test suite

### Definition of Done
- [x] Messages accumulate per-chat for 90 seconds before agent invocation
- [x] Hard `@Andy` mention flushes batch immediately
- [x] Agent response text → WhatsApp reply; agent tool-calls-only → no reply sent
- [x] Session is resumed across invocations (same conversation)
- [x] Self-chat triggers immediately (no batch delay)
- [x] Bot's own messages don't start/extend batch timers
- [x] All tests pass: `uv run pytest pykoclaw-whatsapp/tests/ -v`

### Must Have
- Per-chat batch accumulation with configurable window
- Hard mention immediate flush with timer cancellation
- LLM-driven reply decision (system prompt instructs behavior)
- Session resumption across invocations
- Reply suppression when agent produces no text output
- Per-chat concurrency guard (no parallel agent calls for same chat)
- Tests for all new logic

### Must NOT Have (Guardrails)
- No per-chat configuration or whitelists
- No dedicated memory/knowledge MCP tool (use existing Write tool)
- No explicit interjection delay mechanism (natural batch delay suffices)
- No rate limiting or cost controls (log for observation only)
- No message type expansion (text-only, same as current `extract_text()`)
- No modifications to core pykoclaw code (`agent_core.py`, `db.py`, etc.)
- No session rotation strategy (noted as future work)
- No max-messages-per-batch cap (noted as future work)

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks in this plan MUST be verifiable WITHOUT any human action.

### Test Decision
- **Infrastructure exists**: YES (pytest in dev deps, existing test files)
- **Automated tests**: YES (tests-after — implementation first, then tests covering it)
- **Framework**: pytest (already configured)

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

Every task includes agent-executable verification. Since this is a library/module (not a web UI or API server), verification is via pytest and Python import checks.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
├── Task 1: Add batch_window_seconds config [no dependencies]
└── Task 5: Write tests for all new logic [no dependencies — tests can be written against the planned API before implementation, then verified after]

Wave 2 (After Wave 1):
├── Task 2: Implement BatchAccumulator class [depends: 1]
├── Task 3: Rework _handle_agent_trigger [depends: 1]
└── Task 4: Rework MessageHandler.on_message + system prompt [depends: 2, 3]

Wave 3 (After Wave 2):
└── Task 6: Integration verification — run full test suite [depends: 4, 5]
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2, 3, 4 | 5 |
| 2 | 1 | 4 | 3, 5 |
| 3 | 1 | 4 | 2, 5 |
| 4 | 2, 3 | 6 | — |
| 5 | None | 6 | 1, 2, 3 |
| 6 | 4, 5 | None | — |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1, 5 | `quick` for config; `unspecified-high` for tests |
| 2 | 2, 3, 4 | `unspecified-high` for each |
| 3 | 6 | `quick` for verification |

---

## TODOs

- [x] 1. Add `batch_window_seconds` config setting

  **What to do**:
  - Add `batch_window_seconds: int = Field(default=90)` to `WhatsAppSettings` in `config.py`
  - The env variable will be `PYKOCLAW_WA_BATCH_WINDOW_SECONDS` (auto from `env_prefix`)

  **Must NOT do**:
  - No per-chat config
  - No other config changes

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single-field addition to an existing Pydantic settings class.
  - **Skills**: `[]`
    - No special skills needed.

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 5)
  - **Blocks**: Tasks 2, 3, 4
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py:11-22` — Existing `WhatsAppSettings` class with `auth_dir`, `trigger_name`, `session_db` fields. Add `batch_window_seconds` following the same `Field(default=...)` pattern.

  **Acceptance Criteria**:

  ```
  Scenario: Config loads with default batch window
    Tool: Bash
    Steps:
      1. uv run python -c "from pykoclaw_whatsapp.config import WhatsAppSettings; s = WhatsAppSettings(); print(s.batch_window_seconds)"
    Expected Result: Output is "90"
    Evidence: stdout captured

  Scenario: Config respects environment override
    Tool: Bash
    Steps:
      1. PYKOCLAW_WA_BATCH_WINDOW_SECONDS=30 uv run python -c "from pykoclaw_whatsapp.config import WhatsAppSettings; s = WhatsAppSettings(); print(s.batch_window_seconds)"
    Expected Result: Output is "30"
    Evidence: stdout captured
  ```

  **Commit**: YES
  - Message: `feat(whatsapp): add batch_window_seconds config setting`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py`

---

- [x] 2. Implement `BatchAccumulator` class

  **What to do**:
  - Create a `BatchAccumulator` class in `handler.py` (or a new `batch.py` file — implementer's choice based on size)
  - The class manages per-chat batch state with the following API:
    ```python
    class BatchAccumulator:
        def __init__(self, *, window_seconds: float, loop: asyncio.AbstractEventLoop, flush_callback: Callable[[str], Awaitable[None]]):
            """
            window_seconds: batch debounce window (from config)
            loop: asyncio event loop (for timer scheduling)
            flush_callback: async callable that receives chat_jid when a batch should be processed
            """
        
        def add(self, chat_jid: str) -> None:
            """Called from Go thread. Schedules batch timer for this chat via run_coroutine_threadsafe.
            If a timer already exists for this chat_jid, the timer is NOT reset (first-message-wins).
            If chat is currently being processed (agent running), mark as pending re-flush."""
        
        async def flush_now(self, chat_jid: str) -> None:
            """Immediately flush a specific chat's batch. Cancels any pending timer.
            Called on hard @mention. Acquires per-chat lock before invoking flush_callback."""
        
        async def _timer_expired(self, chat_jid: str) -> None:
            """Internal: called when batch timer expires. Acquires per-chat lock, invokes flush_callback."""
    ```
  - **Per-chat state tracking**:
    - `_timers: dict[str, asyncio.TimerHandle]` — pending timer handles, keyed by chat_jid
    - `_locks: dict[str, asyncio.Lock]` — per-chat locks to prevent concurrent agent calls
    - `_pending_reflush: set[str]` — chats that received new messages while agent was running
  - **Thread safety**: `add()` is called from Go thread. It must use `asyncio.run_coroutine_threadsafe()` to schedule work on the event loop. All timer/lock operations happen on the event loop thread.
  - **Timer behavior**: First message in a batch starts the timer. Subsequent messages within the window do NOT reset it (debounce, not throttle). This prevents indefinitely delaying batches in active chats.
  - **Flush behavior**: When flush fires (timer or hard mention), acquire per-chat lock, invoke `flush_callback(chat_jid)`, remove timer. If new messages arrived during flush (add() was called while lock held), set `_pending_reflush` flag and start a new timer after flush completes.
  - **Hard mention flush**: `flush_now()` cancels any pending timer for the chat, then acquires lock and flushes immediately.

  **Must NOT do**:
  - No DB access in BatchAccumulator — it only tracks timers and chat_jid keys
  - No message content storage — messages are already in SQLite via `store_message()`
  - No direct agent invocation — uses `flush_callback` abstraction

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: asyncio timer management with thread-safety concerns. Requires careful concurrency design.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES (within Wave 2)
  - **Parallel Group**: Wave 2 (with Task 3)
  - **Blocks**: Task 4
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py:230-237` — Existing `asyncio.run_coroutine_threadsafe()` pattern for bridging Go threads to asyncio. Follow this exact pattern for `add()`.
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:65-66` — The asyncio event loop is created as `self._loop = asyncio.new_event_loop()` and runs on a daemon thread. The `BatchAccumulator` receives this loop in its constructor.

  **API/Type References**:
  - Python stdlib `asyncio.TimerHandle` — returned by `loop.call_later()`, has `.cancel()` method
  - Python stdlib `asyncio.Lock` — async context manager, must be used within the event loop thread
  - Python stdlib `asyncio.run_coroutine_threadsafe()` — bridges Go thread to asyncio loop

  **Acceptance Criteria**:

  ```
  Scenario: Batch timer fires after window expires
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_batch.py::test_timer_fires_after_window -v
    Expected Result: PASS — flush_callback called once with correct chat_jid after window_seconds
    Evidence: pytest output

  Scenario: Hard mention flushes immediately and cancels timer
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_batch.py::test_hard_mention_flush -v
    Expected Result: PASS — flush_callback called immediately, pending timer cancelled
    Evidence: pytest output

  Scenario: Per-chat lock prevents concurrent flushes
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_batch.py::test_concurrent_flush_blocked -v
    Expected Result: PASS — second flush waits for first to complete
    Evidence: pytest output

  Scenario: Module imports cleanly
    Tool: Bash
    Steps:
      1. uv run python -c "from pykoclaw_whatsapp.handler import BatchAccumulator; print('OK')"
         (or from pykoclaw_whatsapp.batch if placed in separate file)
    Expected Result: Output is "OK"
    Evidence: stdout captured
  ```

  **Commit**: YES (groups with Task 3)
  - Message: `feat(whatsapp): add BatchAccumulator with per-chat timers and flush logic`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py` (or `batch.py`)

---

- [x] 3. Rework `_handle_agent_trigger` — session resumption + reply suppression + system prompt

  **What to do**:
  - **Session resumption**: Before calling `query_agent()`, look up the conversation's `session_id` and pass it as `resume_session_id`. Follow the exact pattern in `scheduler.py:21-24`:
    ```python
    conv = get_conversation(db, conversation_name)
    resume_session_id = conv.session_id if conv else None
    ```
    Add import: `from pykoclaw.db import get_conversation`
  - **Reply suppression**: After collecting `response_parts`, only send a WhatsApp message if the list is non-empty AND contains non-whitespace text. If the agent only executed tool calls (no text output), do NOT call `self._outgoing_queue.send()` and do NOT log "Agent response sent".
  - **System prompt**: Pass a system prompt to `query_agent()` that instructs the agent as an ambient participant. The prompt should:
    - State the agent's name (from `self._config.trigger_name`)
    - Explain the agent is an ambient participant in a WhatsApp chat
    - **Silence bias** (KEY — from research: over-responding is #1 user complaint): "You are an ambient participant. You observe conversations silently. In the vast majority of batches, you should produce NO text output. Err heavily toward silence. Only reply when: (a) you are directly addressed by name or @mention, (b) there is clear factual misinformation that no one has corrected, or (c) you have crucial missing knowledge that would significantly help the conversation. Do NOT volunteer opinions, make small talk, or interject with tangential information. If you choose not to reply, produce no text output at all — do not explain why you are staying silent."
    - **Tool use guidance**: "You may use tools silently (e.g., writing notes, updating files) even when you choose not to reply. Tool use without a reply is normal and expected."
    - **Hard mention override**: When `hard_mention=True`, append: "This batch contains a direct @mention of your name — you MUST reply to it."
    - Include `chat_jid` so the agent knows which chat it's observing
    - **Name sensitivity**: "People may refer to you by name in various forms — your full name, shortened, with or without @, with punctuation, or even inflected/declined forms in non-English languages. When someone addresses you by any variation of your name, treat it as a direct address and reply."
  - **Signature change**: Add a `hard_mention: bool = False` parameter to `_handle_agent_trigger`. When `True`, the system prompt includes the hard-mention override instruction.
  - **Self-chat**: When `is_self_chat` is True, always set `hard_mention=True` (same as current behavior — self-chat always triggers a reply).

  **Must NOT do**:
  - No changes to `agent_core.py` or `query_agent()` function signature
  - No changes to core pykoclaw DB schema
  - No dedicated "observation mode" vs "reply mode" code path — single method handles both via system prompt

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Multiple concerns (session resumption, reply suppression, system prompt crafting) in a single method. Requires understanding of the agent SDK and existing patterns.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES (within Wave 2, with Task 2)
  - **Parallel Group**: Wave 2 (with Task 2)
  - **Blocks**: Task 4
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `pykoclaw/src/pykoclaw/scheduler.py:21-24` — Session resumption pattern. MUST follow this exactly:
    ```python
    conv = get_conversation(db, task.conversation)
    resume_session_id = None
    if conv and conv.session_id:
        resume_session_id = conv.session_id
    ```
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:118-163` — Current `_handle_agent_trigger` method to be modified. Key areas: line 140 (`query_agent` call — add `resume_session_id` and `system_prompt`), lines 152-155 (reply sending — add conditional).
  - `pykoclaw/src/pykoclaw/agent_core.py:46-56` — `query_agent()` signature showing `system_prompt` and `resume_session_id` parameters are already supported.

  **API/Type References**:
  - `pykoclaw/src/pykoclaw/db.py:127-129` — `get_conversation(db, name)` returns `Conversation | None`
  - `pykoclaw/src/pykoclaw/models.py:4-8` — `Conversation` model with `session_id` field
  - `pykoclaw/src/pykoclaw/agent_core.py:24-30` — `AgentMessage` dataclass with `type` and `text` fields

  **Acceptance Criteria**:

  ```
  Scenario: Session ID is passed to query_agent
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_connection.py::test_session_resumption -v
    Expected Result: PASS — query_agent called with resume_session_id from stored conversation
    Evidence: pytest output

  Scenario: No WhatsApp message sent when agent produces no text
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_connection.py::test_reply_suppression_no_text -v
    Expected Result: PASS — OutgoingQueue.send NOT called when response_parts is empty
    Evidence: pytest output

  Scenario: WhatsApp message sent when agent produces text
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_connection.py::test_reply_sent_with_text -v
    Expected Result: PASS — OutgoingQueue.send IS called with agent's text response
    Evidence: pytest output

  Scenario: Hard mention forces reply instruction in system prompt
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_connection.py::test_hard_mention_system_prompt -v
    Expected Result: PASS — system_prompt passed to query_agent contains "MUST reply" when hard_mention=True
    Evidence: pytest output
  ```

  **Commit**: YES (groups with Task 2)
  - Message: `feat(whatsapp): add session resumption, reply suppression, and ambient system prompt`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`

---

- [x] 4. Rework `MessageHandler.on_message` to use batch accumulator

  **What to do**:
  - **Replace `should_trigger()` usage** (handler.py line 218) with batch accumulator integration.
  - **New `on_message` flow**:
    1. Extract text, store message, update cursors (unchanged — lines 197-210)
    2. Skip batch triggering if `is_from_me` is True (bot's own messages don't start/extend batch timers)
    3. Check for hard mention: `f"@{self._trigger_name}" in text` (case-insensitive check). If found → call `self._batch_accumulator.flush_now(chat_jid)` via `asyncio.run_coroutine_threadsafe()`
    4. Check for self-chat (unchanged logic, lines 212-216). If self-chat → call `flush_now(chat_jid)` (immediate, same as current)
    5. Otherwise → call `self._batch_accumulator.add(chat_jid)` (starts/joins batch timer)
  - **Hard mention detection**: Only `@TriggerName` (with literal `@` prefix) is a hard mention. The case-insensitive check is: `f"@{self._trigger_name}".lower() in text.lower()`. All other name variations (bare name, inflections, etc.) are left to the LLM to interpret via the system prompt — they go through the normal batch path.
  - **Wire `BatchAccumulator`**: Instantiate in `WhatsAppConnection.__init__` or `run()`, pass `self._handle_agent_trigger` (wrapped to accept `chat_jid` and `hard_mention` params) as `flush_callback`.
  - **Pass `hard_mention` flag**: The `flush_callback` needs to know whether the flush was triggered by a hard mention. Options: (a) `flush_now` sets a flag that `flush_callback` reads, or (b) use two different callbacks. The simplest approach: `flush_now` passes `hard_mention=True` to the callback, `_timer_expired` passes `hard_mention=False`.
  - **Remove or deprecate `should_trigger()`**: The function is no longer called. Either delete it (and update `test_handler.py` to remove those tests) or leave it with a deprecation comment. Prefer deletion for cleanliness.

  **Must NOT do**:
  - No changes to `store_message()`, `update_chat_timestamp()`, `update_global_cursor()` — these remain unchanged
  - No filtering of message types — `extract_text()` already handles that
  - No per-chat whitelisting logic

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: This is the integration task tying together BatchAccumulator, MessageHandler, and WhatsAppConnection. Requires understanding all three components.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 2, after Tasks 2 and 3)
  - **Blocks**: Task 6
  - **Blocked By**: Tasks 2, 3

  **References**:

  **Pattern References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py:181-239` — Current `on_message` method. Lines 197-210 (store/cursor update) stay unchanged. Lines 212-237 (trigger check + agent callback) get replaced with batch accumulator logic.
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py:141-152` — Current `should_trigger()` function — to be deleted.
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py:230-237` — Existing `asyncio.run_coroutine_threadsafe()` bridge pattern. The new `flush_now` and `add` calls will use this same pattern from the Go thread.
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py:58-86` — `WhatsAppConnection.run()` where `self._loop` and `self._handler` are created. `BatchAccumulator` should be instantiated here too, with `self._loop` and a callback wrapping `self._handle_agent_trigger`.

  **Test References**:
  - `pykoclaw-whatsapp/tests/test_handler.py:161-169` — Existing `should_trigger` tests. These should be removed when `should_trigger()` is deleted.

  **Acceptance Criteria**:

  ```
  Scenario: Non-mentioned message enters batch (not immediately processed)
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_handler.py::test_non_mention_enters_batch -v
    Expected Result: PASS — batch_accumulator.add() called, agent NOT invoked immediately
    Evidence: pytest output

  Scenario: Hard @mention flushes batch immediately
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_handler.py::test_hard_mention_flushes -v
    Expected Result: PASS — batch_accumulator.flush_now() called, agent invoked with hard_mention=True
    Evidence: pytest output

  Scenario: Self-chat triggers immediate flush
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_handler.py::test_self_chat_immediate -v
    Expected Result: PASS — flush_now() called for self-chat messages
    Evidence: pytest output

  Scenario: Bot's own messages don't trigger batching
    Tool: Bash (pytest)
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_handler.py::test_is_from_me_skipped -v
    Expected Result: PASS — neither add() nor flush_now() called for is_from_me messages
    Evidence: pytest output

  Scenario: should_trigger() is removed
    Tool: Bash
    Steps:
      1. uv run python -c "from pykoclaw_whatsapp.handler import should_trigger" 2>&1 || echo "REMOVED"
    Expected Result: ImportError or "REMOVED" — function no longer exists
    Evidence: stdout captured
  ```

  **Commit**: YES
  - Message: `feat(whatsapp): replace should_trigger with batch-based ambient observation`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/handler.py`, `pykoclaw-whatsapp/src/pykoclaw_whatsapp/connection.py`

---

- [x] 5. Write comprehensive test suite for all new logic

  **What to do**:
  - Create or update test files covering all new functionality:
    - `tests/test_batch.py` — BatchAccumulator unit tests
    - Update `tests/test_handler.py` — Remove `should_trigger` tests, add new `on_message` flow tests
    - Create `tests/test_connection.py` — Session resumption, reply suppression, system prompt tests
  - **Test categories**:

    **BatchAccumulator tests** (`test_batch.py`):
    - `test_timer_fires_after_window`: add() a chat_jid, advance time past window → flush_callback called once
    - `test_multiple_messages_single_flush`: add() same chat_jid 3 times within window → flush_callback called once (not 3 times)
    - `test_independent_chat_timers`: add() to chat_a and chat_b → separate timers, separate flushes
    - `test_hard_mention_flush`: add() then flush_now() before timer expires → immediate flush, timer cancelled
    - `test_hard_mention_includes_accumulated`: add() msg1, then flush_now() → flush_callback called with chat_jid (which will pull msg1 from DB)
    - `test_concurrent_flush_blocked`: Two concurrent flush_now() calls → second waits for first
    - `test_pending_reflush`: add() while flush is running → new timer starts after flush completes
    - `test_is_from_me_not_triggering`: Verify at MessageHandler level, not BatchAccumulator (accumulator doesn't know about is_from_me)
    - `test_empty_batch_skipped`: flush fires but get_new_messages_for_chat returns [] → no agent invocation

    **Connection tests** (`test_connection.py`):
    - `test_session_resumption`: Mock get_conversation to return session_id → verify query_agent called with resume_session_id
    - `test_session_resumption_no_existing`: No conversation exists → resume_session_id is None
    - `test_reply_suppression_no_text`: Mock query_agent to yield only AgentMessage(type="result") → OutgoingQueue.send NOT called
    - `test_reply_suppression_empty_text`: Mock query_agent to yield AgentMessage(type="text", text="") → OutgoingQueue.send NOT called
    - `test_reply_sent_with_text`: Mock query_agent to yield AgentMessage(type="text", text="Hello") → OutgoingQueue.send called
    - `test_hard_mention_system_prompt`: hard_mention=True → system_prompt contains "MUST reply"
    - `test_ambient_system_prompt`: hard_mention=False → system_prompt contains "Only reply if"
    - `test_system_prompt_includes_trigger_name`: System prompt contains the configured trigger_name

    **Handler tests** (update `test_handler.py`):
    - Remove `test_should_trigger_with_mention` and `test_should_trigger_self_chat`
    - `test_non_mention_enters_batch`: Message without @mention → batch_accumulator.add() called
    - `test_hard_mention_flushes`: Message with @Andy → batch_accumulator.flush_now() called
    - `test_hard_mention_case_insensitive`: Message with @andy → flush_now() called
    - `test_self_chat_immediate`: Self-chat message → flush_now() called
    - `test_is_from_me_skipped`: is_from_me message → neither add() nor flush_now() called
    - `test_status_broadcast_skipped`: status@broadcast messages still skipped (unchanged)

  - **Testing patterns**: Follow existing patterns in `test_handler.py`:
    - In-memory SQLite with `pytest.fixture`
    - `unittest.mock.Mock` for neonize types
    - `pytest.importorskip("neonize")` at top of files that need neonize mocks
  - **Async testing**: BatchAccumulator tests need async fixtures. Add `pytest-asyncio` to dev dependencies. Use `@pytest.mark.asyncio` decorator.
  - **Time control**: For timer tests, use `asyncio` event loop with manual time advancement, or `unittest.mock.patch` on `loop.call_later` to capture callbacks and invoke them manually.

  **Must NOT do**:
  - No integration tests requiring a running WhatsApp connection
  - No tests that import neonize without `pytest.importorskip`
  - No tests that make real API calls to Claude

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Comprehensive test suite with async fixtures, mock patterns, and multiple test files. Requires understanding all new components.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1) — test skeletons can be written against planned API
  - **Blocks**: Task 6
  - **Blocked By**: None (tests written against planned API, verified in Task 6)

  **References**:

  **Pattern References**:
  - `pykoclaw-whatsapp/tests/test_handler.py:1-54` — Existing test patterns: imports, `pytest.importorskip("neonize")`, in-memory DB fixture, mock message construction.
  - `pykoclaw-whatsapp/tests/test_handler.py:173-199` — Mock MessageEv construction pattern using `unittest.mock.Mock` with `HasField` lambda.
  - `pykoclaw-whatsapp/tests/test_queue.py` — Queue test patterns (if useful for OutgoingQueue mock setup).

  **External References**:
  - pytest-asyncio docs: `https://pytest-asyncio.readthedocs.io/en/latest/` — For `@pytest.mark.asyncio` and async fixtures

  **Acceptance Criteria**:

  ```
  Scenario: All tests pass
    Tool: Bash
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/ -v
    Expected Result: All tests PASS, 0 failures
    Evidence: pytest output captured

  Scenario: pytest-asyncio is available
    Tool: Bash
    Steps:
      1. uv run python -c "import pytest_asyncio; print('OK')"
    Expected Result: Output is "OK"
    Evidence: stdout captured
  ```

  **Commit**: YES
  - Message: `test(whatsapp): add comprehensive tests for ambient participation mode`
  - Files: `pykoclaw-whatsapp/tests/test_batch.py`, `pykoclaw-whatsapp/tests/test_handler.py`, `pykoclaw-whatsapp/tests/test_connection.py`, `pykoclaw-whatsapp/pyproject.toml`
  - Pre-commit: `uv run pytest pykoclaw-whatsapp/tests/ -v`

---

- [x] 6. Integration verification — run full test suite

  **What to do**:
  - Run the complete test suite to verify all components work together
  - Verify no import errors across the package
  - Verify config loads correctly
  - Verify existing tests still pass (no regressions)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Just running commands and verifying output.
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (final)
  - **Blocks**: None
  - **Blocked By**: Tasks 4, 5

  **References**:
  - All files from Tasks 1-5

  **Acceptance Criteria**:

  ```
  Scenario: Full test suite passes
    Tool: Bash
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/ -v
    Expected Result: All tests PASS, 0 failures, 0 errors
    Evidence: Full pytest output captured to .sisyphus/evidence/task-6-full-suite.txt

  Scenario: Package imports cleanly
    Tool: Bash
    Steps:
      1. uv run python -c "from pykoclaw_whatsapp.handler import MessageHandler, BatchAccumulator; from pykoclaw_whatsapp.config import WhatsAppSettings; print('All imports OK')"
    Expected Result: Output is "All imports OK"
    Evidence: stdout captured

  Scenario: Config loads with new field
    Tool: Bash
    Steps:
      1. uv run python -c "from pykoclaw_whatsapp.config import WhatsAppSettings; s = WhatsAppSettings(); assert s.batch_window_seconds == 90; print('Config OK')"
    Expected Result: Output is "Config OK"
    Evidence: stdout captured

  Scenario: No regressions in existing handler tests
    Tool: Bash
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_handler.py -v
    Expected Result: All existing tests (format_xml, store_message, extract_text, etc.) still PASS
    Evidence: pytest output

  Scenario: No regressions in existing queue tests
    Tool: Bash
    Steps:
      1. uv run pytest pykoclaw-whatsapp/tests/test_queue.py -v
    Expected Result: All queue tests still PASS
    Evidence: pytest output
  ```

  **Commit**: NO (verification only)

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(whatsapp): add batch_window_seconds config setting` | config.py | import check |
| 2+3 | `feat(whatsapp): add BatchAccumulator and rework agent trigger with session resumption` | handler.py (or batch.py), connection.py | import check |
| 4 | `feat(whatsapp): replace should_trigger with batch-based ambient observation` | handler.py, connection.py | import check |
| 5 | `test(whatsapp): add comprehensive tests for ambient participation mode` | tests/*, pyproject.toml | `uv run pytest pykoclaw-whatsapp/tests/ -v` |

---

## Success Criteria

### Verification Commands
```bash
# Full test suite
uv run pytest pykoclaw-whatsapp/tests/ -v
# Expected: All tests PASS

# Package imports
uv run python -c "from pykoclaw_whatsapp.handler import MessageHandler; print('OK')"
# Expected: OK

# Config default
uv run python -c "from pykoclaw_whatsapp.config import WhatsAppSettings; s = WhatsAppSettings(); print(s.batch_window_seconds)"
# Expected: 90

# should_trigger removed
uv run python -c "from pykoclaw_whatsapp.handler import should_trigger" 2>&1; echo "exit: $?"
# Expected: ImportError, exit: 1
```

### Final Checklist
- [x] Messages accumulate in 90-second batches per chat
- [x] Hard `@TriggerName` mention flushes batch immediately
- [x] LLM decides whether to reply via system prompt (not string matching)
- [x] Agent response text → WhatsApp message; tool-calls-only → silence
- [x] Session resumed across invocations (same conversation)
- [x] Self-chat triggers immediately
- [x] Bot's own messages don't trigger batch accumulation
- [x] Per-chat lock prevents concurrent agent calls
- [x] All tests pass
- [x] No modifications to core pykoclaw code
- [x] `should_trigger()` removed

### Future Work (Out of Scope — informed by research)
- **Session rotation** (HIGH PRIORITY for production): Research shows accuracy degrades after ~200 turns / ~17K tokens. At 90-second batches with ~10 messages each, this is ~5 hours of active group chat. Recommended: rotate every 24 hours with a summary carryover. CoChat and SimpleMem show 30x token reduction with summarization.
- **Tiered memory system**: Working memory (current batch) → Session memory (last 24h, semantic search) → Long-term memory (vector-searchable facts). CoChat's architecture achieves 97% cost reduction.
- **Participation rate tracking**: cloneme tracks what % of messages the agent contributes. Setting a hard cap (e.g., <30% in groups) prevents the over-responding problem that research identifies as the #1 user complaint.
- **Decision caching with TTL**: cloneme caches reply decisions (security: 1h, classification: 30m, information value: 10m). Prevents re-evaluating identical patterns.
- **Semantic caching for similar messages**: Can reduce LLM costs by up to 73% (wa_llm findings).
- Max-messages-per-batch cap
- Per-chat configuration / whitelists
- Dedicated memory/knowledge MCP tool
- Cost monitoring / rate limiting
- Message type expansion (images, stickers, reactions)
- Privacy-aware memory isolation (different memory rules for group chats vs DMs — CoChat pattern)
