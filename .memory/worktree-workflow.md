# Feature Worktree Workflow

**Tags:** worktree, git, dev-workflow, multi-repo
**Related:** [workspace-layout.md]

Multi-repo feature worktrees let you develop across all pykoclaw repos on a
single feature branch without touching `main`.

- **Create:** `bin/create-worktree.sh <feature>` → branches + worktrees + uv sync + AoE
- **List:** `bin/list-worktrees.sh`
- **Run dev:** `bin/run-dev.sh <feature>` → isolated ports + temp data dirs
- **QA:** `bin/qa-check.sh <feature>` → pytest + Mitto tests
- **Cleanup:** `bin/cleanup-worktree.sh <feature>` → removes worktrees + AoE + temp dirs
- **Branches not auto-deleted** — clean up manually after cleanup
- Layout: `~/pykoclaw-dev/<feature>/{root,pykoclaw,pykoclaw-acp,...}`
- AoE integration is optional (graceful degradation)
- Full docs: `docs/worktree-workflow.md`

[workspace-layout.md]: workspace-layout.md
