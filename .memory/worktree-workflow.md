# Feature Worktree Workflow

**Tags:** worktree, git, dev-workflow, multi-repo
**Related:** [workspace-layout.md]

Multi-repo feature worktrees let you develop across all pykoclaw repos on a
single feature branch without touching `main`.

## Scripts

- **Create:** `bin/create-worktree.sh <feature>` → branches + worktrees + uv sync + AoE
- **List:** `bin/list-worktrees.sh`
- **Run dev:** `bin/run-dev.sh <feature>` → isolated ports + temp data dirs
- **QA:** `bin/qa-check.sh <feature>` → pytest + Mitto tests
- **Merge:** `bin/merge-feature.sh <feature>` → merge feature branches → main
- **Cleanup:** `bin/cleanup-worktree.sh <feature>` → removes worktrees + AoE + temp dirs
- **Branches not auto-deleted** — clean up manually after cleanup
- Layout: `~/pykoclaw-dev/<feature>/{pykoclaw,pykoclaw-acp,...}`
- AoE integration is optional (graceful degradation)
- Full docs: `docs/worktree-workflow.md`

## Standard landing lifecycle (rebase → review → merge → deploy → cleanup)

When landing a feature, follow this exact sequence:

1. **Fetch + rebase** all repos in the worktree onto `origin/main`
2. **Review** what the branch brings: `git log --oneline origin/main..HEAD`
   across all repos to find which have changes, then `git diff` on those
3. **Merge:** `bin/merge-feature.sh <feature>`
4. **Deploy + cleanup:** `./install-dev.sh && bin/cleanup-worktree.sh <feature>`
5. **Restart Mitto** if ACP changes were merged

When landing multiple worktrees, complete the full cycle for each before
starting the next — this keeps `origin/main` current for the next rebase.

## Multi-repo diff review pattern

To quickly see what a feature branch brings across all repos:

```bash
cd ~/pykoclaw-dev/<feature>
for d in . pykoclaw pykoclaw-chat pykoclaw-whatsapp pykoclaw-messaging pykoclaw-acp; do
  commits=$(git -C "$d" log --oneline origin/main..HEAD 2>/dev/null)
  [ -n "$commits" ] && echo "=== $d ===" && echo "$commits" && echo
done
```

Then `git diff origin/main..HEAD` only in repos with changes.

[workspace-layout.md]: workspace-layout.md
