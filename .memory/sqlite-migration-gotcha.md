# SQLite CREATE TABLE IF NOT EXISTS never adds missing columns

**Tags:** sqlite, gotcha, migration, schema
**Related:** [sdk-schema-gotcha.md]

`CREATE TABLE IF NOT EXISTS` silently does **nothing** if the table already
exists — even if the existing table is missing columns from the current schema.
SQLite does not diff columns or add missing ones.

## The trap

You add a column to a `CREATE TABLE IF NOT EXISTS` statement and all tests
pass because tests use fresh temporary databases. But any user with a database
created before the column was added will silently be stuck on the old schema
until they delete and recreate their database.

## Required pattern

Whenever you add a column to a `CREATE TABLE IF NOT EXISTS`, also add:

1. **Migration logic** in `init_db()`:
   ```python
   _add_column(db, "table_name", "new_column TEXT DEFAULT 'value'")
   ```

2. **Upgrade test** in `test_db.py`:
   ```python
   def test_init_db_adds_new_column_to_existing_table(tmp_path):
       # Create DB with old schema (without the new column)
       raw = sqlite3.connect(str(tmp_path / "test.db"))
       raw.execute("CREATE TABLE table_name (...old columns...)")
       raw.close()
       # init_db should add the missing column
       db = init_db(tmp_path / "test.db")
       cols = [r[1] for r in db.execute("PRAGMA table_info(table_name)")]
       assert "new_column" in cols
   ```

[sdk-schema-gotcha.md]: sdk-schema-gotcha.md
