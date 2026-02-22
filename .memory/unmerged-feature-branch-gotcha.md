# Unmerged Feature Branch Gotcha

**Tags:** git, worktree, gotcha, dev-workflow
**Related:** [worktree-workflow.md]

Features committed to a `feature/*` branch but never merged into `main` are
silently missing at runtime. This has happened at least once (WhatsApp
Markdown formatter: committed to `feature/whatsapp-markdown`, `main` left
at the parent commit).

**Symptom:** code exists in git history and passes all tests on the feature
branch, but has no effect in production because the branch was never merged.

**Detection:**

```bash
# List commits on feature branch not yet in main
git log --oneline feature/<name> ^main

# Check if a specific file exists on main
git ls-tree main src/pykoclaw_whatsapp/formatting.py
```

**Prevention:** after completing a feature worktree, always run
`bin/merge-feature.sh <feature>` before moving on. Don't assume "committed"
means "deployed" — in the worktree workflow they are separate steps.

**Fix:** cherry-pick the missing commits from the feature branch onto a new
fix worktree, confirm tests pass, then merge.

[worktree-workflow.md]: worktree-workflow.md
