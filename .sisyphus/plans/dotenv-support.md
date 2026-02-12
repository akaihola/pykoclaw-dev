# Add `.env` File Support to pykoclaw

## TL;DR

> **Quick Summary**: Enable pykoclaw to read settings from `.env` files in the current working directory and the data directory, using pydantic-settings' built-in dotenv support.
>
> **Deliverables**:
> - Core `Settings` reads `.env` files
> - `WhatsAppSettings` reads `.env` files (migrated to `model_config` style)
> - Tests covering the new behaviour and protecting existing tests from accidental `.env` loading
>
> **Estimated Effort**: Quick
> **Parallel Execution**: NO — sequential (3 small tasks with dependencies)
> **Critical Path**: Task 1 → Task 2 → Task 3

---

## Context

### Original Request
User wants `.env` file support so settings like `PYKOCLAW_WA_TRIGGER_NAME` can be configured without exporting environment variables. Files should be loaded from the CWD and from the `PYKOCLAW_DATA` directory.

### Interview Summary
**Key Discussions**:
- `.env` chosen over TOML because pydantic-settings already supports it natively — zero new dependencies
- `python-dotenv` is already a transitive dependency of `pydantic-settings`, no `pyproject.toml` change needed
- Precedence: env vars > CWD `.env` > data dir `.env`

### Metis Review
**Identified Gaps** (addressed):
- **Chicken-and-egg with `PYKOCLAW_DATA`**: If a user overrides `PYKOCLAW_DATA` via env var, the data dir `.env` path can't dynamically follow because `model_config` is evaluated at class definition time. Resolution: use the static default path (`~/.local/share/pykoclaw/.env`). This is the common case; users who set custom env vars can continue using env vars.
- **WhatsApp `class Config:` is deprecated style**: Must migrate to `model_config = {...}` dict style while adding `env_file`.
- **Test contamination risk**: Existing tests calling `Settings()` or `WhatsAppSettings()` with no arguments will start loading `.env` files if one exists in the test working directory. Must protect tests.

---

## Work Objectives

### Core Objective
Add `.env` file loading to both `Settings` and `WhatsAppSettings` using pydantic-settings' built-in `env_file` support.

### Concrete Deliverables
- `pykoclaw/src/pykoclaw/config.py` — updated `model_config` with `env_file`
- `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py` — migrated to `model_config` dict + `env_file`
- New/updated tests in both packages

### Definition of Done
- [ ] `uv run pytest pykoclaw/tests/ -x -q` passes
- [ ] `uv run pytest pykoclaw-whatsapp/tests/ -x -q` passes
- [ ] Settings are read from CWD `.env` when present
- [ ] Settings are read from `~/.local/share/pykoclaw/.env` when present
- [ ] Env vars override `.env` values
- [ ] Missing `.env` files cause no errors

### Must Have
- `.env` file loading from CWD (`.env` relative path)
- `.env` file loading from default data dir (`~/.local/share/pykoclaw/.env`)
- Env vars override `.env` values
- Both `Settings` and `WhatsAppSettings` support `.env`
- Existing tests remain green

### Must NOT Have (Guardrails)
- No `.env.example` template files
- No CLI `config show` command
- No `settings_customise_sources()` override (keep it simple)
- No new dependencies added to `pyproject.toml`
- No changes to files outside the two `config.py` files and their tests
- No changes to settings behaviour beyond adding `.env` loading

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (pytest)
- **Automated tests**: YES (tests-after — add targeted tests for new behaviour)
- **Framework**: pytest

---

## TODOs

- [x] 1. Add `env_file` support to core `Settings`

  **What to do**:
  - In `pykoclaw/src/pykoclaw/config.py`, update `model_config` to add `env_file` and `env_file_encoding`:
    ```python
    model_config = {
        "env_prefix": "PYKOCLAW_",
        "env_file": (
            str(Path.home() / ".local" / "share" / "pykoclaw" / ".env"),
            ".env",
        ),
        "env_file_encoding": "utf-8",
    }
    ```
  - The tuple order puts the data dir `.env` first (lower priority) and CWD `.env` second (higher priority). pydantic-settings gives later entries higher priority.

  **Must NOT do**:
  - Do not use `settings_customise_sources()`
  - Do not add dependencies
  - Do not change any other fields or behaviour of `Settings`

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: Task 2, Task 3
  - **Blocked By**: None

  **References**:
  - `pykoclaw/src/pykoclaw/config.py:6-17` — Current `Settings` class (the only file to modify)
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py:7-8` — Compare: `model_config` dict style vs `class Config:` style

  **Acceptance Criteria**:
  - [ ] `model_config` dict contains `env_file` tuple with two paths
  - [ ] `model_config` dict contains `env_file_encoding` set to `"utf-8"`
  - [ ] No new imports added beyond what's already there (`Path` is already imported)

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Core Settings reads PYKOCLAW_MODEL from CWD .env
    Tool: Bash
    Preconditions: No PYKOCLAW_MODEL env var set
    Steps:
      1. Create temp dir: TMPDIR=$(mktemp -d)
      2. Write .env: echo 'PYKOCLAW_MODEL=test-model-from-dotenv' > "$TMPDIR/.env"
      3. Run from that dir:
         cd "$TMPDIR" && uv run --project /home/agent/pykoclaw/pykoclaw python -c "
         from pykoclaw.config import Settings
         s = Settings()
         assert s.model == 'test-model-from-dotenv', f'Expected test-model-from-dotenv, got {s.model}'
         print('PASS')
         "
    Expected Result: Prints "PASS" — model value read from .env
    Failure Indicators: AssertionError or import error

  Scenario: Env var overrides CWD .env value
    Tool: Bash
    Preconditions: None
    Steps:
      1. Create temp dir with .env containing PYKOCLAW_MODEL=from-dotenv
      2. Run with PYKOCLAW_MODEL=from-env-var set:
         cd "$TMPDIR" && PYKOCLAW_MODEL=from-env-var uv run --project /home/agent/pykoclaw/pykoclaw python -c "
         from pykoclaw.config import Settings
         s = Settings()
         assert s.model == 'from-env-var', f'Expected from-env-var, got {s.model}'
         print('PASS')
         "
    Expected Result: Prints "PASS" — env var wins

  Scenario: Missing .env files cause no error
    Tool: Bash
    Preconditions: Empty temp dir with no .env
    Steps:
      1. cd $(mktemp -d) && uv run --project /home/agent/pykoclaw/pykoclaw python -c "
         from pykoclaw.config import Settings
         s = Settings()
         print('PASS:', s.model)
         "
    Expected Result: Prints "PASS: claude-opus-4-6" — default used, no crash
  ```

  **Commit**: YES
  - Message: `feat(config): add .env file support to core Settings`
  - Files: `pykoclaw/src/pykoclaw/config.py`

---

- [ ] 2. Add `env_file` support to `WhatsAppSettings` (migrate from `class Config:`)

  **What to do**:
  - In `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py`, replace the deprecated `class Config:` block with `model_config` dict style, adding `env_file` and `env_file_encoding`:
    ```python
    class WhatsAppSettings(BaseSettings):
        model_config = {
            "env_prefix": "PYKOCLAW_WA_",
            "env_file": (
                str(Path.home() / ".local" / "share" / "pykoclaw" / ".env"),
                ".env",
            ),
            "env_file_encoding": "utf-8",
        }

        auth_dir: Path = Field(default=Path.home() / ".pykoclaw" / "whatsapp" / "auth")
        trigger_name: str = Field(default="Andy")
        # ... rest unchanged
    ```
  - Remove the nested `class Config:` block entirely.

  **Must NOT do**:
  - Do not change field names, types, or defaults
  - Do not modify `get_config()` function
  - Do not add dependencies

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (after Task 1)
  - **Blocks**: Task 3
  - **Blocked By**: Task 1

  **References**:
  - `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py:11-23` — Current `WhatsAppSettings` class with deprecated `class Config:` (lines 21-22)
  - `pykoclaw/src/pykoclaw/config.py:7` — Pattern to follow: `model_config` dict style (after Task 1 updates it)

  **Acceptance Criteria**:
  - [ ] `class Config:` block is removed
  - [ ] `model_config` dict matches the core `Settings` pattern (with `PYKOCLAW_WA_` prefix)
  - [ ] Same `env_file` tuple as core `Settings`
  - [ ] All existing fields (`auth_dir`, `trigger_name`, `session_db`, `batch_window_seconds`) unchanged

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: WhatsApp trigger_name read from CWD .env
    Tool: Bash
    Preconditions: No PYKOCLAW_WA_TRIGGER_NAME env var set
    Steps:
      1. Create temp dir, write .env with PYKOCLAW_WA_TRIGGER_NAME=TestBot
      2. Run:
         cd "$TMPDIR" && uv run --project /home/agent/pykoclaw/pykoclaw-whatsapp python -c "
         from pykoclaw_whatsapp.config import WhatsAppSettings
         s = WhatsAppSettings()
         assert s.trigger_name == 'TestBot', f'Expected TestBot, got {s.trigger_name}'
         print('PASS')
         "
    Expected Result: Prints "PASS"

  Scenario: Both prefixes work from same .env file
    Tool: Bash
    Steps:
      1. Write .env with both PYKOCLAW_MODEL=custom and PYKOCLAW_WA_TRIGGER_NAME=CustomBot
      2. Instantiate both Settings and WhatsAppSettings
      3. Assert each reads its own prefixed values
    Expected Result: Each class picks up its own prefix from the shared .env
  ```

  **Commit**: YES (group with Task 1)
  - Message: `feat(config): add .env file support to WhatsAppSettings`
  - Files: `pykoclaw-whatsapp/src/pykoclaw_whatsapp/config.py`

---

- [ ] 3. Add and fix tests for `.env` loading behaviour

  **What to do**:
  - **Core tests** (`pykoclaw/tests/`): Add a test file or tests to an existing file covering:
    - `.env` in CWD is loaded
    - Env var overrides `.env`
    - Missing `.env` is fine
  - **WhatsApp tests** (`pykoclaw-whatsapp/tests/`): Same coverage, plus:
    - Verify `trigger_name` can be set via `.env`
  - **Protect existing tests**: Ensure existing tests that instantiate `Settings()` or `WhatsAppSettings()` without arguments aren't contaminated by a `.env` file in the test runner's CWD. Use `monkeypatch.chdir(tmp_path)` or pass `_env_file=None` to the constructor in tests that need pristine defaults. Check all test files for bare `Settings()` / `WhatsAppSettings()` calls.

  **Must NOT do**:
  - Do not modify source files (only test files)
  - Do not add integration tests requiring WhatsApp connection

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (after Task 2)
  - **Blocks**: None
  - **Blocked By**: Task 1, Task 2

  **References**:
  - `pykoclaw/tests/test_plugins.py:125-126` — Existing test that creates a `BaseSettings` subclass (pattern reference)
  - `pykoclaw-whatsapp/tests/test_whatsapp_plugin.py:92-98` — Tests `WhatsAppSettings()` defaults directly — **must protect from .env contamination**
  - `pykoclaw-whatsapp/tests/test_connection.py:53-55` — Constructs `WhatsAppSettings(trigger_name="Andy")` explicitly — less risky but check
  - `pykoclaw-whatsapp/tests/test_handler.py:194,212` — Uses `trigger_name` param — not affected

  **Acceptance Criteria**:
  - [ ] `uv run pytest pykoclaw/tests/ -x -q` → all pass
  - [ ] `uv run pytest pykoclaw-whatsapp/tests/ -x -q` → all pass
  - [ ] At least one test verifies `.env` loading works (CWD `.env` read by Settings)
  - [ ] At least one test verifies env var overrides `.env`
  - [ ] Existing tests that rely on defaults are protected from `.env` contamination

  **Agent-Executed QA Scenarios**:

  ```
  Scenario: Full test suite passes
    Tool: Bash
    Steps:
      1. uv run pytest pykoclaw/tests/ -x -q
      2. uv run pytest pykoclaw-whatsapp/tests/ -x -q
    Expected Result: Both pass with 0 failures
    Failure Indicators: Any FAILED or ERROR lines

  Scenario: New .env tests specifically pass
    Tool: Bash
    Steps:
      1. uv run pytest pykoclaw/tests/ -k "env" -v
    Expected Result: New dotenv-related tests show PASSED
  ```

  **Commit**: YES
  - Message: `test(config): add tests for .env file loading`
  - Files: `pykoclaw/tests/test_config.py` (new or existing), `pykoclaw-whatsapp/tests/test_whatsapp_plugin.py`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1+2 | `feat(config): add .env file support` | both `config.py` files | `uv run pytest` both packages |
| 3 | `test(config): add tests for .env file loading` | test files | `uv run pytest` both packages |

---

## Success Criteria

### Verification Commands
```bash
uv run pytest pykoclaw/tests/ -x -q       # Expected: all pass
uv run pytest pykoclaw-whatsapp/tests/ -x -q  # Expected: all pass
```

### Final Checklist
- [ ] Both `Settings` and `WhatsAppSettings` have `env_file` in `model_config`
- [ ] `WhatsAppSettings` migrated from `class Config:` to `model_config` dict
- [ ] CWD `.env` is loaded with higher priority than data dir `.env`
- [ ] Env vars override all `.env` values
- [ ] Missing `.env` files are silently ignored
- [ ] No new dependencies added
- [ ] All existing tests still pass
- [ ] No `.env.example` or CLI config commands added
