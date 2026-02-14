# Decisions — DB Layer Improvements

## [2026-02-12T21:20:55Z] Plan Decisions
- NO ORM (Oracle recommendation) — raw SQL is proportional to scale (3 tables, ~260 lines)
- Sequential execution with frequent commits (user requested)
- Test files remain unchanged (valid `sqlite3.Connection` usage)
