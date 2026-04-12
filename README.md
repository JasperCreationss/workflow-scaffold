# workflow-scaffold

A portable Claude Code workflow that drops into any project. Installs hooks, settings, and a bootstrap meta-skill that walks your codebase to generate tailored domain `SKILL.md` files and a populated `CLAUDE.md`.

Designed to answer one question: *"How do I give Claude the same context-loading workflow across every project I manage, without hand-maintaining it in each one?"*

## Install

Audit first (recommended):

```bash
curl -fsSL https://raw.githubusercontent.com/JasperCreationss/workflow-scaffold/main/install.sh -o install.sh
less install.sh
bash install.sh
```

Or in one shot, if you trust the source:

```bash
curl -fsSL https://raw.githubusercontent.com/JasperCreationss/workflow-scaffold/main/install.sh | bash
```

From a local checkout (useful for development and testing):

```bash
bash /path/to/workflow-scaffold/install.sh --local /path/to/workflow-scaffold
```

## What gets installed

The installer is **non-destructive** — it only adds files that don't already exist:

- `.claude/settings.json` — minimal hooks baseline (read-tracker enabled)
- `.claude/hooks/read-tracker.sh` — logs Read tool calls per session
- `.claude/hooks/optional/psql-gate.sh` — opt-in DB quick-reference gate
- `.claude/skills/_bootstrap/SKILL.md` — the meta-skill (runs once, then archives itself)
- `.claude/.gitignore` — ignores `tmp/`, `*.scaffold-baseline`, `*.proposed`
- `CLAUDE.md` — template at the project root

Nothing else lands at your project root. No loose scripts, no temp dirs.

If `.claude/settings.json` already exists, the installer writes the baseline to `.claude/settings.json.scaffold-baseline` for manual merge instead of overwriting.

## The bootstrap flow

After install, open Claude Code in your project and tell it:

> Run the bootstrap skill

The meta-skill walks 8 phases:

1. **Survey** — identify project shape, language, frameworks
2. **Identify candidate domains** — list directories that warrant a SKILL.md (user approves)
3. **Detect cross-cutting concerns** — DB usage, test framework, external services
4. **Deep-read each approved domain** — extract tables, file paths, conventions
5. **Draft SKILL.md files** — one per approved domain, with CSO-style triggers
6. **Generate CLAUDE.md** — project name, tech stack, Context Map, commands, DB quick reference
7. **Configure hooks** — enable optional hooks based on what was detected
8. **Self-archive** — rename to `_bootstrap-refresh/` so it stays available for incremental updates

It stops after each checkpoint phase for your review. Skill spam is the failure mode — the human-in-the-loop checkpoints exist to prevent it.

## Upgrade

To pull newer hook implementations from the scaffold repo without touching your skills or CLAUDE.md:

```bash
bash install.sh --upgrade
```

This re-copies `.claude/hooks/` only. Skills, templates, and settings are left alone.

## Pinning to a release

```bash
bash install.sh --ref v0.1.0
```

## Clean-root constraint

The scaffold places everything under `.claude/` (hidden project config) plus a single `CLAUDE.md` at the root. This matches the clean-root philosophy: project roots should hold top-level config and `.md` files only, not loose scripts or clutter.

The scaffold repo itself practices this — the only non-`.md` file at its own root is `install.sh`, which is architecturally required to be there for the curl one-liner to work.

## Limitations

- **Linux / macOS / WSL only.** Hook scripts are Bash; Windows-native is unsupported.
- **The meta-skill is non-deterministic.** It uses Claude to read your codebase and write skills. Always review the output before committing.
- **No CI tests yet.** Manual test flow: install into a tmp dir, verify files, re-run to confirm idempotency.

## Repo layout

```
workflow-scaffold/
├── README.md
├── CLAUDE.md                 # for Claude working on the scaffold itself
├── LICENSE
├── install.sh                # the curl-able installer
├── scaffold/                 # payload — copied verbatim into .claude/
│   ├── settings.json
│   ├── .gitignore
│   ├── hooks/
│   │   ├── read-tracker.sh
│   │   └── optional/
│   │       └── psql-gate.sh
│   └── skills/
│       └── _bootstrap/
│           └── SKILL.md      # the meta-skill
└── templates/                # rendered into target project root
    ├── CLAUDE.md.tmpl
    └── AGENTS.md.tmpl
```

## License

MIT
