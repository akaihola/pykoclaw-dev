#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# ///
"""Query and visualize the pykoclaw backlog from .sisyphus/plans/ metadata.

Reads ## Status:, ## Priority:, and > **Estimated Effort** / > **Depends On**
from plan files and outputs:

  --format table   Ranked Markdown table (default)
  --format mermaid Mermaid dependency graph
  --format full    Both table and Mermaid, suitable for BACKLOG.md

Filters:
  --status Backlog          Only show plans with this status
  --status Backlog,Done     Comma-separated list
  --all                     Show all statuses (default: Backlog only)

Sort:
  --sort priority           Sort by priority number ascending (default)
  --sort effort             Sort by estimated effort
  --sort name               Sort alphabetically

Output:
  --output FILE             Write to file instead of stdout
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from textwrap import dedent


PLANS_DIR = Path(__file__).parent / "plans"

EFFORT_ORDER = {
    "quick": 1,
    "short": 2,
    "medium": 3,
    "medium-large": 4,
    "large": 5,
}

STATUS_SYMBOLS = {
    "done": "\u2705",
    "in progress": "\U0001f6a7",
    "backlog": "\U0001f4cb",
    "blocked": "\u26d4",
}


@dataclass
class Plan:
    filename: str
    title: str = ""
    status: str = "Backlog"
    priority: int = 99
    effort: str = ""
    depends_on: list[str] = field(default_factory=list)
    summary: str = ""

    @property
    def slug(self) -> str:
        return self.filename.removesuffix(".md")

    @property
    def status_icon(self) -> str:
        return STATUS_SYMBOLS.get(self.status.lower(), "\u2753")

    @property
    def effort_sort_key(self) -> int:
        return EFFORT_ORDER.get(self.effort.lower().split("(")[0].strip(), 99)


def parse_plan(path: Path) -> Plan:
    """Parse a plan file and extract structured metadata."""
    text = path.read_text(encoding="utf-8")
    plan = Plan(filename=path.name)

    # Title: first # heading
    m = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    if m:
        plan.title = m.group(1).strip()

    # Status: ## Status: <value>
    m = re.search(r"^##\s*Status:\s*(.+)$", text, re.MULTILINE)
    if m:
        plan.status = m.group(1).strip()

    # Priority: ## Priority: <number>
    m = re.search(r"^##\s*Priority:\s*(\d+)", text, re.MULTILINE)
    if m:
        plan.priority = int(m.group(1))

    # Estimated Effort from TL;DR block
    m = re.search(r"\*\*Estimated Effort\*\*:\s*(.+?)(?:\n|$)", text)
    if m:
        plan.effort = m.group(1).strip()

    # Dependencies: > **Depends On**: [name](file) or [name]
    m = re.search(r"\*\*Depends On\*\*:\s*(.+?)(?:\n|$)", text)
    if m:
        deps_text = m.group(1).strip()
        # Extract filenames from markdown links [name](file) or [name]
        dep_links = re.findall(r"\[([^\]]+)\](?:\([^)]*\))?", deps_text)
        if dep_links:
            plan.depends_on = [
                d.removesuffix(".md") for d in dep_links
            ]
        elif deps_text.lower() not in ("none", "—", "-", "n/a"):
            # Plain text dependency
            plan.depends_on = [
                d.strip().removesuffix(".md")
                for d in deps_text.split(",")
                if d.strip()
            ]

    # Also check for "## Depends On:" header style
    m = re.search(r"^##\s*Depends On:\s*(.+)$", text, re.MULTILINE)
    if m and not plan.depends_on:
        deps_text = m.group(1).strip()
        if deps_text.lower() not in ("none", "—", "-", "n/a"):
            plan.depends_on = [
                d.strip().removesuffix(".md")
                for d in deps_text.split(",")
                if d.strip()
            ]

    # Quick Summary from TL;DR
    m = re.search(
        r"\*\*Quick Summary\*\*:\s*(.+?)(?:\n>?\s*\n|\n>\s*\*\*)",
        text,
        re.DOTALL,
    )
    if m:
        summary = m.group(1).strip()
        # Collapse multiline > quoted text
        summary = re.sub(r"\n>\s*", " ", summary)
        # Truncate for table display
        if len(summary) > 120:
            summary = summary[:117] + "..."
        plan.summary = summary

    return plan


def load_plans() -> list[Plan]:
    """Load all plan files from the plans directory."""
    plans = []
    for path in sorted(PLANS_DIR.glob("*.md")):
        plans.append(parse_plan(path))
    return plans


def sort_plans(plans: list[Plan], sort_key: str) -> list[Plan]:
    """Sort plans by the given key."""
    if sort_key == "priority":
        return sorted(plans, key=lambda p: (p.priority, p.effort_sort_key, p.title))
    elif sort_key == "effort":
        return sorted(plans, key=lambda p: (p.effort_sort_key, p.priority, p.title))
    elif sort_key == "name":
        return sorted(plans, key=lambda p: p.title.lower())
    return plans


def format_table(plans: list[Plan]) -> str:
    """Format plans as a Markdown table."""
    lines = [
        "| # | Status | Plan | Effort | Depends On |",
        "|---|--------|------|--------|------------|",
    ]
    for i, p in enumerate(plans, 1):
        deps = ", ".join(p.depends_on) if p.depends_on else "\u2014"
        effort = p.effort or "\u2014"
        lines.append(
            f"| {i} | {p.status_icon} {p.status} | **{p.title}** | {effort} | {deps} |"
        )
    return "\n".join(lines)


def format_mermaid(plans: list[Plan]) -> str:
    """Format plans as a Mermaid dependency graph."""
    lines = ["```mermaid", "graph LR"]

    # Build slug-to-plan mapping for style classes
    slug_map = {p.slug: p for p in plans}

    # Define nodes with short labels
    for p in plans:
        slug = p.slug
        short_title = p.title
        if len(short_title) > 40:
            short_title = short_title[:37] + "..."

        if p.status.lower() == "done":
            lines.append(f'    {slug}["{short_title}"]')
        elif p.status.lower() == "in progress":
            lines.append(f'    {slug}{{{{"{short_title}"}}}}')
        else:
            lines.append(f'    {slug}(["{short_title}"])')

    lines.append("")

    # Add dependency edges
    has_edges = False
    for p in plans:
        for dep in p.depends_on:
            has_edges = True
            lines.append(f"    {dep} --> {p.slug}")

    if not has_edges:
        lines.append("    %% No dependencies defined yet")

    lines.append("")

    # Style classes
    lines.append("    classDef done fill:#2d5a2d,stroke:#4a4,color:#cfc")
    lines.append(
        "    classDef backlog fill:#4a3a1a,stroke:#a84,color:#fc9"
    )
    lines.append(
        "    classDef inprogress fill:#1a3a5a,stroke:#48a,color:#9cf"
    )

    done_slugs = [p.slug for p in plans if p.status.lower() == "done"]
    backlog_slugs = [p.slug for p in plans if p.status.lower() == "backlog"]
    inprogress_slugs = [
        p.slug for p in plans if p.status.lower() == "in progress"
    ]

    if done_slugs:
        lines.append(f"    class {','.join(done_slugs)} done")
    if backlog_slugs:
        lines.append(f"    class {','.join(backlog_slugs)} backlog")
    if inprogress_slugs:
        lines.append(f"    class {','.join(inprogress_slugs)} inprogress")

    lines.append("```")
    return "\n".join(lines)


def format_full(plans: list[Plan], backlog_only: list[Plan]) -> str:
    """Format full BACKLOG.md content with table + Mermaid."""
    sections = [
        "# Pykoclaw Backlog",
        "",
        "_Auto-generated by `query_backlog.py`. Do not edit manually._",
        "",
        "## Priority Queue",
        "",
    ]

    if backlog_only:
        sections.append(format_table(backlog_only))
    else:
        sections.append("_No items in backlog. All plans are done!_ \U0001f389")

    sections.extend([
        "",
        "## Dependency Graph",
        "",
        "All plans (done + backlog) and their dependencies:",
        "",
        format_mermaid(plans),
        "",
        "## Completed Plans",
        "",
    ])

    done = [p for p in plans if p.status.lower() == "done"]
    if done:
        sections.append(format_table(done))
    else:
        sections.append("_No completed plans yet._")

    sections.extend(["", f"---", f"_Last generated: see git log_", ""])
    return "\n".join(sections)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Query and visualize pykoclaw backlog"
    )
    parser.add_argument(
        "--format",
        choices=["table", "mermaid", "full"],
        default="table",
        help="Output format (default: table)",
    )
    parser.add_argument(
        "--status",
        help="Filter by status (comma-separated, e.g. 'Backlog,In Progress')",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Show all statuses (default: Backlog only for table/mermaid)",
    )
    parser.add_argument(
        "--sort",
        choices=["priority", "effort", "name"],
        default="priority",
        help="Sort order (default: priority)",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        help="Write output to file instead of stdout",
    )
    args = parser.parse_args()

    all_plans = load_plans()

    # Filter
    if args.format == "full" or args.all:
        filtered = all_plans
    elif args.status:
        statuses = {s.strip().lower() for s in args.status.split(",")}
        filtered = [p for p in all_plans if p.status.lower() in statuses]
    else:
        filtered = [p for p in all_plans if p.status.lower() == "backlog"]

    # Sort
    filtered = sort_plans(filtered, args.sort)

    # Format
    if args.format == "table":
        output = format_table(filtered)
    elif args.format == "mermaid":
        output = format_mermaid(filtered)
    elif args.format == "full":
        backlog_only = sort_plans(
            [p for p in all_plans if p.status.lower() != "done"],
            args.sort,
        )
        output = format_full(all_plans, backlog_only)

    # Output
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
        print(f"Written to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
