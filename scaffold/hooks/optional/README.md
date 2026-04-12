# Optional hooks

Hooks in this directory are **disabled by default**. The bootstrap meta-skill (`.claude/skills/_bootstrap/SKILL.md`) enables them during Phase 7 if the relevant condition is detected in your codebase (e.g. `psql-gate.sh` is enabled only when a database is detected).

## Manual activation

If you want to enable an optional hook without running the meta-skill:

1. Move the hook file from `.claude/hooks/optional/` to `.claude/hooks/`
2. Add the corresponding entry to `.claude/settings.json`

### `psql-gate.sh` — PreToolUse on Bash

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/psql-gate.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/read-tracker.sh"
          }
        ]
      }
    ]
  }
}
```

`psql-gate.sh` depends on `read-tracker.sh` already being active — that's what populates the per-session read log that `psql-gate.sh` checks. The `read-tracker.sh` entry ships enabled by default, so you only need to add the `PreToolUse` block.

**Payoff gate:** `psql-gate.sh` is only useful if your `CLAUDE.md` has a database quick-reference section — the hook points users there. Without that section, the hook is pure friction. The meta-skill writes both at once for this reason; if you're enabling manually, write the quick reference yourself first.
