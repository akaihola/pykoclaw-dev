# Scheduler: relative time support for `once` tasks

## Status: Backlog
## Priority: 10

## TL;DR

> **Quick Summary**: The `schedule_task` MCP tool requires absolute UTC
> timestamps for `once` tasks. The agent has no internal clock, so it must run
> `date`, convert from the user's timezone (Europe/Helsinki) to UTC, and format
> as ISO 8601. This caused three rounds of rescheduling in one session — wrong
> timezone assumption, then user typo, then another reschedule.
>
> Support relative time strings like `+1m`, `+5m`, `+1h` in `schedule_value`
> for `once` tasks. The scheduler resolves to absolute time server-side,
> eliminating timezone conversion errors entirely.
>
> **Estimated Effort**: Quick
> **Depends On**: (none)

---

## Motivation

When the agent needs to schedule something "in a minute", it must:
1. Run `date` to discover current time
2. Know the user's timezone (Europe/Helsinki)
3. Convert to UTC
4. Format as ISO 8601

Each step is an error opportunity. In the session that triggered this, all four
steps went wrong at least once. Relative times eliminate steps 2–4.

## Expected Outcome

- `schedule_value: "+5m"` schedules 5 minutes from now
- `schedule_value: "+1h"` schedules 1 hour from now
- `schedule_value: "+30s"` schedules 30 seconds from now
- Only applies to `schedule_type: "once"` — cron and interval are unchanged
- Absolute ISO 8601 timestamps continue to work as before

## Implementation

In `pykoclaw/src/pykoclaw/scheduler.py`, when processing a `once` task:

```python
import re
from datetime import datetime, timedelta, timezone

def _resolve_schedule_value(schedule_type: str, value: str) -> str:
    """Resolve relative time strings to absolute UTC timestamps."""
    if schedule_type != "once":
        return value

    match = re.fullmatch(r"\+(\d+)([smh])", value.strip())
    if not match:
        return value  # assume absolute ISO 8601

    amount, unit = int(match.group(1)), match.group(2)
    delta = timedelta(
        seconds=amount if unit == "s" else 0,
        minutes=amount if unit == "m" else 0,
        hours=amount if unit == "h" else 0,
    )
    target = datetime.now(timezone.utc) + delta
    return target.isoformat()
```

Also update the MCP tool schema description for `schedule_value` to document
the relative time format.

## Related

- [schedule-task-optional-params.md] — Previous schema fix for this tool (Done)

[schedule-task-optional-params.md]: schedule-task-optional-params.md
