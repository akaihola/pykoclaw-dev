# Config tests fail when PYKOCLAW_DATA is set in the environment

## Status: Done

## Completed: 2026-03-25

**Goal:** Make `pykoclaw/tests/test_config.py` pass regardless of whether
`PYKOCLAW_DATA` (or other `PYKOCLAW_*` variables) are set in the outer
environment.

**User experience:** Running `PYKOCLAW_DATA=/tmp/foo uv run pytest` causes 4
spurious test failures, making it impossible to run the test suite from a
context where `PYKOCLAW_DATA` is set (e.g. a deployment script, a CI job with
environment pre-configured, or manual testing with `export PYKOCLAW_DATA=…`).

## Root cause

Four tests in `test_config.py` assert that `settings.data` equals a specific
value (either the platform default or a path from a `.env` file), but they
don't clear `PYKOCLAW_DATA` from the process environment. Since Pydantic
Settings gives env vars higher precedence than `.env` files, any
`PYKOCLAW_DATA` inherited from the outer shell overrides the expected value.

Affected tests:

| Test | Class | Missing cleanup |
|---|---|---|
| `test_settings_defaults_no_env_file` | `TestSettingsDefaults` | No `delenv("PYKOCLAW_DATA")` |
| `test_settings_db_path_property` | `TestSettingsDefaults` | No `delenv("PYKOCLAW_DATA")` |
| `test_settings_loads_custom_data_path_from_env` | `TestSettingsEnvFileLoading` | No `delenv("PYKOCLAW_DATA")` |
| `test_settings_loads_multiple_vars_from_env` | `TestSettingsEnvFileLoading` | No `delenv("PYKOCLAW_DATA")` |

## Fix

Add `monkeypatch.delenv("PYKOCLAW_DATA", raising=False)` to each affected
test, or – better – add a session/class-scoped autouse fixture that clears all
`PYKOCLAW_*` env vars before every config test. This is the same pattern
already used for `BRAVE_API_KEY` in `TestBraveApiKey`.

Pi-Session: 57da183c-3904-4966-9a48-acd44cc590c0
Pi-Session-File: /home/agent/.pi/agent/sessions/--home-agent-prg-pykoclaw-dev--/2026-03-25T07-15-26-749Z_57da183c-3904-4966-9a48-acd44cc590c0.jsonl
