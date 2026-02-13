## [2026-02-11] Task 7: WhatsApp message loop implementation

### libmagic System Dependency Issue

**Problem**: Neonize requires `libmagic` system library, which is not available in the current NixOS environment.

**Error**:
```
ImportError: failed to find libmagic.  Check your installation
```

**Impact**:
- Cannot run `pykoclaw whatsapp run` command
- Cannot test MCP server creation (imports handler.py which imports neonize)
- Message storage tests work (don't require neonize import)

**Identified in**: Task 5 spike findings

**Workaround**: On systems with libmagic installed (Debian/Ubuntu: `apt install libmagic1`), the code should work correctly.

**Verification Status**:
- ✅ Acceptance criterion 3: Message storage works
- ⚠️ Acceptance criterion 1: Run command blocked by libmagic
- ⚠️ Acceptance criterion 2: MCP server blocked by libmagic

**Code Quality**: All ruff checks pass after fixing unused imports.

**Implementation Complete**: All required files created (connection.py, handler.py, queue.py), all patterns ported from NanoClaw, dual-cursor model implemented, asyncio bridge implemented.
