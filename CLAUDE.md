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

Two layers:

- **CI** (`.github/workflows/test.yml`) — runs on every push to `main` and every PR. Two jobs:
  - `hook-tests` — runs every `scaffold/hooks/**/*.test.sh` under grouped logs. Drop a new `<name>.test.sh` next to a new hook and it's picked up automatically.
  - `install-smoke` — fresh install via `install.sh --local`, asserts the expected file set landed with exec bits and the wired matchers, reruns and fails on any non-`skip` line, then tampers a hook + reruns with `--upgrade` to prove scope.
- **Manual flow** (for local iteration before pushing):
  1. `mkdir /tmp/scaffold-test && cd /tmp/scaffold-test`
  2. `git init` (so the sanity check passes)
  3. `bash /path/to/workflow-scaffold/install.sh --local /path/to/workflow-scaffold`
  4. Verify `.claude/` structure and `CLAUDE.md` at root
  5. Run again — verify `skip` lines for every file (idempotency)
  6. Modify `.claude/settings.json`, run again — verify `.scaffold-baseline` sidecar is written

## Review gate

Every `feat/` and `fix/` PR runs through a three-reviewer pass before merge. Exempt: pure `docs/` PRs and one-line cosmetic fixes.

The three reviewers, in parallel:

- **`security-auditor`** — bash safety (quoting, IFS, regex/glob injection, path traversal in hook stdin), installer supply-chain surface (curl-pipe-bash, `--ref` pinning, action SHA pinning), hook contract (stdin handling, exit-code discipline, info disclosure via stderr).
- **`senior-dev-auditor`** — correctness against docstring claims, idempotency / `--upgrade` scope, CI workflow assertions actually proving what they say, portability across the README's supported matrix (Linux + macOS stock Bash 3.2 + WSL).
- **`codex review --base main`** — independent model (GPT-5-based) for diversity. Different training, different blind spots than the Claude pair.

**Codex reviews, Claude fixes.** Codex is the adversarial second opinion; Claude decides what's real and edits. Don't let two models fight over style.

**Adapt prompts to the scaffold's stack** — the auditor agents originated in lynxnsw-dev with Hono/tRPC/Mantine-specific checks. When invoking them here, scope to bash + GitHub Actions concerns and explicitly exclude Node/TS/SQL findings.

Treat findings as signal: investigate every flag, dismiss only with a written reason. The scaffold has no human second reviewer; this gate is the backstop.

## Don't

- Don't add Node, Python, or any runtime dep to the installer
- Don't ship hook scripts that hardcode project-specific knowledge. That belongs in the meta-skill's generated output, not in `scaffold/hooks/`.
- Don't put loose files at the repo root
- Don't let the installer do anything the meta-skill should do. The division is: installer = static copy, meta-skill = codebase-aware generation
