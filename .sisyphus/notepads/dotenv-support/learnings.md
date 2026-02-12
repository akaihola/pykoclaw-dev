# Learnings & Conventions

(Agents: append findings here after task completion)

## Task 1: Core Settings env_file Support - COMPLETED

### Implementation Summary
- Updated `model_config` in `pykoclaw/src/pykoclaw/config.py` with:
  - `env_file` tuple: `(str(Path.home() / ".local" / "share" / "pykoclaw" / ".env"), ".env")`
  - `env_file_encoding`: `"utf-8"`
- No new imports needed (Path already imported)
- No changes to Settings fields or class structure

### Pydantic-Settings Behavior Confirmed
1. **Tuple order matters**: First path (data dir `.env`) has lower priority, second path (CWD `.env`) has higher priority
2. **Precedence chain** (highest to lowest):
   - Environment variables (e.g., `PYKOCLAW_MODEL=from-env-var`)
   - CWD `.env` file (`.env` in current working directory)
   - Data dir `.env` file (`~/.local/share/pykoclaw/.env`)
   - Field defaults (e.g., `model: str = "claude-opus-4-6"`)
3. **Missing files are safe**: pydantic-settings silently skips non-existent `.env` files, no crashes

### Test Results
- ✓ All 16 existing pytest tests pass
- ✓ Scenario 1: CWD `.env` loads correctly
- ✓ Scenario 2: Environment variables take precedence over `.env`
- ✓ Scenario 3: Defaults used when no `.env` or env vars present
- ✓ LSP diagnostics: No errors

### Key Gotchas Avoided
- Did NOT use `settings_customise_sources()` (unnecessary complexity)
- Did NOT add new dependencies (python-dotenv is transitive)
- Did NOT modify Settings fields or class structure
- Tuple syntax for `env_file` is critical for pydantic-settings to load multiple files in order

### Ready for Task 2
WhatsAppSettings can now follow the same pattern with its own data directory path.
