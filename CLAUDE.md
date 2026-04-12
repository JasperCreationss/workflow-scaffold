# CLAUDE.md — workflow-scaffold

This is the source repo for `workflow-scaffold`, a portable Claude Code workflow installer. When working on this repo, follow these conventions.

## Repo layout

- `install.sh` — single-file Bash installer, the only executable at the repo root
- `scaffold/` — payload directory. Everything here is copied verbatim into a target project's `.claude/` on install.
- `templates/` — files rendered into a target project's root on install (currently `CLAUDE.md.tmpl`, `AGENTS.md.tmpl`)
- Repo root: `.md` files + `LICENSE` + `install.sh`, nothing else. No loose scripts, no `package.json`, no dotfiles other than what git requires. The repo practices the clean-root constraint it imposes on installed projects.

**Why `install.sh` is at the root (exception to clean-root):** architecturally required for the curl one-liner (`curl URL/install.sh | bash`). Nesting it under `bin/` would make install URLs uglier without any gain.

## Conventions

- **Bash only.** No runtime dependencies. The installer must work on Linux, macOS, and WSL with nothing more than `curl`, `tar`, and `bash`.
- **Idempotent install.** `bash install.sh` must be safely re-runnable. Install mode never overwrites existing target-project files — settings.json gets a `.scaffold-baseline` sidecar instead.
- **Hooks use `$CLAUDE_PROJECT_DIR`** for paths so they work regardless of where the project is checked out.
- **Hook output goes to stderr.** Stdout from `PostToolUse` hooks is injected into Claude's context — use sparingly.
- **The meta-skill is the brain.** Most of the intelligence lives in `scaffold/skills/_bootstrap/SKILL.md`, not in `install.sh`. Keep the installer dumb and predictable; push complexity into the meta-skill where the user is in the loop.

## Editing the meta-skill

`scaffold/skills/_bootstrap/SKILL.md` defines the 8-phase bootstrap flow. When editing:

- Preserve the phase checkpoints (stop + wait for user) on phases 1, 2, 4, 5, 6. These are what prevent skill spam.
- The frontmatter `description:` is what the native Skill tool matches against. Keep it concrete.
- Hard rules at the bottom are load-bearing — don't relax them without a specific reason.

## Testing

No automated test suite yet. Manual flow:

1. `mkdir /tmp/scaffold-test && cd /tmp/scaffold-test`
2. `git init` (so the sanity check passes)
3. `bash /path/to/workflow-scaffold/install.sh --local /path/to/workflow-scaffold`
4. Verify `.claude/` structure and `CLAUDE.md` at root
5. Run again — verify `skip` lines for every file (idempotency)
6. Modify `.claude/settings.json`, run again — verify `.scaffold-baseline` sidecar is written

## Don't

- Don't add Node, Python, or any runtime dep to the installer
- Don't ship hook scripts that hardcode project-specific knowledge. That belongs in the meta-skill's generated output, not in `scaffold/hooks/`.
- Don't put loose files at the repo root
- Don't let the installer do anything the meta-skill should do. The division is: installer = static copy, meta-skill = codebase-aware generation
