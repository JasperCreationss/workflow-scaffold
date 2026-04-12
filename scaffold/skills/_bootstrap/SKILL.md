---
name: bootstrap
description: Use ONCE per project to bootstrap the workflow-scaffold setup. Trigger when the user says "run the bootstrap skill", "bootstrap this project", or "set up workflow-scaffold", typically right after a fresh install.sh run. Walks the codebase across 8 phases to identify domains, generate tailored SKILL.md files, populate CLAUDE.md, and configure optional hooks. Self-archives to _bootstrap-refresh after running.
---

# Bootstrap Meta-Skill

You are about to bootstrap the workflow-scaffold for this project. Your job is to walk the codebase and produce a tailored Claude Code workflow: domain `SKILL.md` files, a populated `CLAUDE.md`, and the right set of optional hooks enabled.

**Execute this in 8 phases. Stop and report after each phase. Do not proceed to the next phase without user confirmation.** The human-in-the-loop checkpoints are not optional — they prevent skill spam and bad-context generation. Skill spam (30 skills for a 10-domain project, or skills with generic descriptions that never fire) is the failure mode this workflow exists to avoid.

---

## Phase 1 — Survey (read-only)

Goal: build a one-paragraph mental model of the project before deciding anything.

Steps:
1. List top-level directories
2. Identify config files at the root: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `pom.xml`, `composer.json`, `mix.exs`, `deno.json`, etc.
3. Read the project root README if one exists
4. Check `.git/config` for the remote URL to infer project name
5. Identify primary language(s) and major frameworks from the config files
6. Identify monorepo shape: look for `services/`, `packages/`, `apps/`, `src/`, `database/`, `lib/`, `cmd/`, `crates/`

Report:
- Project name (from config or git remote)
- Primary language(s) and major frameworks
- Top-level directory inventory (one line each, purpose inferred where possible)
- Single-service or multi-service shape

**Stop. Wait for user confirmation before Phase 2.**

---

## Phase 2 — Identify candidate domains

Goal: list every directory that warrants its own `SKILL.md`. Be strict — this is where skill spam is born.

A domain **qualifies** if it has at least one of:
- An existing README.md or AGENTS.md
- A clearly bounded purpose (a service, a schema, a CLI tool)
- More than ~10 source files sharing a concern

A domain **does not qualify** if it:
- Is a build output, vendor dir, or generated code
- Is a single-purpose utility folder with no documentation
- Duplicates the scope of another candidate

Report a table:

| Candidate | Path | Evidence | Recommended? |
|-----------|------|----------|--------------|
| ...       | ...  | ...      | yes/no       |

Then ask the user to approve, remove, or add candidates. **Wait for explicit approval before Phase 3.** Do not proceed on assumed approval.

---

## Phase 3 — Detect cross-cutting concerns

Goal: decide what optional hooks to enable and what shows up in the Context Map.

Check for:
- **Database usage** — grep for `psql`, `postgres`, `pg`, `sqlite`, `mysql`, `prisma`, `drizzle`, `sequelize`, `sqlalchemy`, `knex`, `typeorm`; look for `.sql` files and migration dirs. If found, flag `psql-gate.sh` for activation and plan to write a DB quick reference into CLAUDE.md.
- **Test framework** — `package.json` scripts, `pytest.ini`, `Cargo.toml` `[dev-dependencies]`, etc.
- **Build/deploy tooling** — `Dockerfile`, `docker-compose.yml`, CI configs (`.github/workflows/`, `.gitlab-ci.yml`), infrastructure code
- **External services** — search for known SDK imports (Slack, Resend, Twilio, AWS, Stripe, etc.)

Report findings as a list, then add: *"If anything above looks wrong (false negative on DB detection, missed service, etc.), tell me now — I'll proceed to Phase 4 otherwise."* This is a soft checkpoint: no explicit approval needed, but the user gets one line of invitation to correct you before Phase 4 burns the file-read budget on wrong assumptions.

---

## Phase 4 — Deep-read each approved domain

Goal: extract enough concrete facts per domain to write a useful `SKILL.md`.

For each domain approved in Phase 2:
- Read the domain's README if present
- Read 3-8 representative source files (not all of them)
- Extract: key tables/types/functions, important file paths, naming conventions, gotchas from code comments

**Budget:** cap reading at ~30 files total across all domains. If you'd blow the budget, stop and ask the user to narrow scope — reading more files is not a substitute for a tighter domain list.

Do not invent facts. If a domain is opaque after the budget is spent, that's a signal to write a stub SKILL.md pointing at the directory and move on.

Report a per-domain summary (3-5 bullets each). **Stop. Wait for user confirmation before Phase 5.**

---

## Phase 5 — Draft SKILL.md files

Goal: write one `SKILL.md` per approved domain.

Required structure:

```markdown
---
name: <kebab-case-domain-name>
description: Use when <specific triggers packed with concrete names from Phase 4>
---

# <Domain Title>

<One-paragraph summary>

## Key files

- `path/to/thing.ext` — purpose
- ...

## Key tables/types/functions

- `name` — purpose
- ...

## Conventions

- ...

## Gotchas

- ...
```

Rules:
- The `description:` field IS the activation logic. A generic description never fires. Pack it with concrete triggers — table names, file paths, function names, terminology that would appear in a user prompt about this domain.
- **Never overwrite an existing `SKILL.md`.** If one exists at the target path, write to `SKILL.md.proposed` next to it and report.
- Write each file to `.claude/skills/<domain-name>/SKILL.md`.

Report a list of files created. **Stop. Wait for user review before Phase 6.**

---

## Phase 6 — Generate CLAUDE.md (and AGENTS.md if multi-service)

Goal: populate the root `CLAUDE.md` template with project-specific content.

The template has placeholders like `{{PROJECT_NAME}}`, `{{TECH_STACK_TABLE}}`, `{{CONTEXT_MAP_TABLE}}`, `{{COMMANDS}}`, `{{DB_QUICK_REFERENCE}}`, `{{CONVENTIONS}}`. Fill them in from Phases 1, 3, 4, and 5:

- **Project name** — from Phase 1
- **Tech stack** — services × stack table
- **Context Map** — topic → authoritative file. Derived from the skills you wrote in Phase 5 and any READMEs found in Phase 4. This is the single most valuable section — a future Claude reads it before exploring the codebase.
- **Commands** — extract from `package.json` scripts, `Makefile`, `justfile`, etc.
- **DB quick reference** — only if Phase 3 detected a database. Include column-level info for the most-queried tables. This is what gives `psql-gate.sh` its payoff — without this section, the hook is friction with no reward.
- **Conventions** — infer from linter configs, editorconfig, existing code style. Be conservative.

Rules:
- If `CLAUDE.md` already has hand-edited content (more than just the template placeholders), do not overwrite. Write the proposed content to `CLAUDE.md.proposed` and report the diff.
- If multi-service was detected in Phase 1: also generate `AGENTS.md` at the root with per-service pointers. Same non-destructive rule applies.

**Stop. Wait for user review before Phase 7.**

---

## Phase 7 — Configure hooks

Goal: enable the right optional hooks based on Phase 3 findings.

For each file in `.claude/hooks/optional/`:
- If its activation condition was met in Phase 3:
  - Move it from `.claude/hooks/optional/` into `.claude/hooks/`
  - Add the corresponding entry to `.claude/settings.json`
- Otherwise: leave it in `optional/`

Specifics:
- **psql-gate.sh** — only enable if the DB quick reference was actually written to CLAUDE.md in Phase 6. The hook without the documentation is friction with no payoff.

Report which hooks were enabled and show the `settings.json` diff.

---

## Phase 8 — Self-archive and final report

Goal: leave the workflow re-runnable but not auto-triggering.

1. Rename `.claude/skills/_bootstrap/` to `.claude/skills/_bootstrap-refresh/`
2. Edit this `SKILL.md` frontmatter `description:` to:
   > `Use ONLY when explicitly asked to refresh or regenerate the workflow-scaffold skills after major codebase changes. Do NOT trigger on routine prompts. Only runs in refresh mode — never overwrites existing files.`
3. Print a final summary:
   - Skills created (count + names)
   - Hooks enabled
   - `CLAUDE.md` / `AGENTS.md` status (created vs `.proposed`)
   - Anything skipped and why

Tell the user:

> Bootstrap complete. Review with `git status` and `git diff`, then commit when satisfied.

---

## Refresh mode (after rename to `_bootstrap-refresh`)

When invoked in refresh mode, the rules change:

- **Never overwrite an existing `SKILL.md`.** Always write to `SKILL.md.proposed` and let the user diff.
- **Never overwrite `CLAUDE.md`.** Always write to `CLAUDE.md.proposed`.
- Phases 1-3 still run. Phase 2 should explicitly highlight new directories that didn't exist on the previous run.
- Phases 5-6 produce only `.proposed` files.
- Phase 7 only adds hooks, never removes.
- Phase 8 is a no-op (already archived).

This makes the workflow incrementally updatable without ever clobbering user edits.

---

## Hard rules

1. **Stop after every checkpoint phase** (1, 2, 4, 5, 6). Do not batch through. The user approves each phase before you start the next.
2. **Never invent facts.** If you can't read enough to write a useful skill, write a stub that says so. A truthful "I don't know this domain" beats a confidently-wrong SKILL.md.
3. **Never overwrite user files in install mode.** `settings.json`, `CLAUDE.md`, and existing `SKILL.md` files are sacred. Write `.proposed` sidecars instead.
4. **Skill descriptions are the activation logic.** A skill with a generic description is worse than no skill at all — it never fires and clutters the registry. Pack descriptions with concrete triggers from the codebase.
5. **Clean root.** The installer has already satisfied this constraint by placing everything under `.claude/` + the single root `CLAUDE.md`. Do not create additional loose files at the project root during bootstrap. If you need scratch space, use `.claude/tmp/`.
