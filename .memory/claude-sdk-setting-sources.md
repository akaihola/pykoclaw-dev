# Claude SDK: `setting_sources` Controls Skill Discovery and Precedence

**Tags:** claude-sdk, skills, agent-core, gotcha, configuration
**Related:** [agent_core.py], [claude-sdk-stderr-silence.md]

## What `setting_sources` does

`ClaudeAgentOptions(setting_sources=[...])` maps to the `--setting-sources`
CLI flag. It controls which Claude config layers are loaded. Values:

- `"project"` — loads `./.claude/` (project-level skills, settings)
- `"user"` — loads `~/.claude/` (user-level skills, settings)

**Without `"user"`**, skills in `~/.claude/skills/` are silently ignored.
**Without `"project"`**, skills in `./.claude/skills/` are silently ignored.

## Order determines precedence

Skills are concatenated in the order specified, and name lookups use `.find()`
(first match wins). Therefore:

- `["project", "user"]` → **project skills supersede user skills** ✓ (correct)
- `["user", "project"]` → user skills supersede project skills (wrong)

**Always use `["project", "user"]`** to get both layers with project taking
priority over user-level skills of the same name.

## Skills are NOT injected via code

Skills (SKILL.md files) are loaded **natively by the Claude CLI** based on
`setting_sources`. Do NOT manually read SKILL.md files and inject them into
`system_prompt` — the CLI handles this automatically.

## Bundled skills cannot be disabled by name

Skills like `keybindings-help` are compiled into the `claude` binary
(`source: "bundled"`) and are not affected by `setting_sources`. The only
way to suppress all bundled skills is `extra_args={"disable-slash-commands": None}`,
which disables ALL slash commands — there is no per-skill disable mechanism.

## Current setting in agent_core.py

```python
ClaudeAgentOptions(
    setting_sources=["project", "user"],  # project skills win on name collision
    ...
)
```

[agent_core.py]: ../pykoclaw/src/pykoclaw/agent_core.py
[claude-sdk-stderr-silence.md]: claude-sdk-stderr-silence.md
