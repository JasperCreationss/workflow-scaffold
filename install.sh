#!/usr/bin/env bash
# workflow-scaffold installer
#
# Drops a Claude Code workflow into any project: hooks, settings.json,
# skills/_bootstrap meta-skill, and a CLAUDE.md template at the project root.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/JasperCreationss/workflow-scaffold/main/install.sh -o install.sh
#   less install.sh              # audit before running
#   bash install.sh              # install in cwd
#   bash install.sh --upgrade    # refresh hook implementations only
#   bash install.sh --ref v0.1.0 # pin to a release tag
#   bash install.sh --repo OWNER/REPO --ref main
#
# Idempotent: safely re-runnable. Install mode never overwrites existing
# files — settings.json gets a .scaffold-baseline sidecar instead.

set -euo pipefail

SCAFFOLD_REPO="${SCAFFOLD_REPO:-JasperCreationss/workflow-scaffold}"
SCAFFOLD_REF="${SCAFFOLD_REF:-main}"
SCAFFOLD_LOCAL="${SCAFFOLD_LOCAL:-}"
MODE="install"

print_help() {
    cat <<EOF
workflow-scaffold installer

Usage:
  bash install.sh [--upgrade] [--repo OWNER/REPO] [--ref REF] [--local PATH]

Flags:
  --upgrade         Re-copy hook implementations only (never touches skills/).
  --repo OWNER/REPO Override scaffold source repo (default: $SCAFFOLD_REPO).
  --ref REF         Branch or tag to pull (default: $SCAFFOLD_REF).
  --local PATH      Install from a local scaffold checkout instead of fetching.
                    PATH should contain scaffold/ and templates/ directories.
  -h, --help        This message.

Modes:
  install (default) Non-destructive. Adds missing files, never overwrites.
                    If settings.json exists, the baseline is written to
                    .claude/settings.json.scaffold-baseline for manual merge.
  upgrade           Re-copies scaffold/hooks/ over .claude/hooks/, replacing
                    existing hook scripts. Skills and CLAUDE.md untouched.

After install: open Claude Code in this directory and ask it to
"run the bootstrap skill". The meta-skill walks you through the rest.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --upgrade) MODE="upgrade"; shift ;;
        --repo) SCAFFOLD_REPO="$2"; shift 2 ;;
        --ref) SCAFFOLD_REF="$2"; shift 2 ;;
        --local) SCAFFOLD_LOCAL="$2"; shift 2 ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown flag: $1" >&2; print_help >&2; exit 1 ;;
    esac
done

# Sanity: looks like a project root?
if [[ ! -d .git ]] && [[ ! -f package.json ]] && [[ ! -f pyproject.toml ]] && \
   [[ ! -f Cargo.toml ]] && [[ ! -f go.mod ]] && [[ ! -f Gemfile ]] && \
   [[ ! -f pom.xml ]] && [[ ! -f composer.json ]] && [[ ! -f mix.exs ]]; then
    echo "Warning: $(pwd) does not look like a project root." >&2
    echo "  (no .git, package.json, pyproject.toml, Cargo.toml, go.mod, Gemfile, pom.xml, composer.json, mix.exs)" >&2
    if [[ ! -t 0 ]]; then
        echo "Error: stdin is not a terminal (pipe-install detected); cannot prompt for confirmation." >&2
        echo "To install into a non-project directory, download first and run interactively:" >&2
        echo "  curl -fsSL <URL> -o install.sh && bash install.sh" >&2
        exit 1
    fi
    read -r -p "Continue anyway? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# Required tools
for tool in curl tar find; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: $tool is required but not installed." >&2
        exit 1
    fi
done

# Validate --repo format (OWNER/REPO with URL-safe characters)
if [[ ! "$SCAFFOLD_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "Error: invalid --repo value: $SCAFFOLD_REPO" >&2
    echo "  Expected format: OWNER/REPO (letters, digits, _, ., -)" >&2
    exit 1
fi

# --- Acquire scaffold source ---
if [[ -n "$SCAFFOLD_LOCAL" ]]; then
    if [[ ! -d "$SCAFFOLD_LOCAL/scaffold" ]]; then
        echo "Error: --local $SCAFFOLD_LOCAL does not contain scaffold/" >&2
        exit 1
    fi
    SRC="$SCAFFOLD_LOCAL"
    echo "Using local scaffold at $SRC"
else
    # Local variable — do NOT name this TMPDIR, which is a system env var
    # on macOS that subprocesses (tar, curl) may read to pick a scratch dir.
    _SCAFFOLD_TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$_SCAFFOLD_TMPDIR"' EXIT
    TARBALL_URL="https://codeload.github.com/${SCAFFOLD_REPO}/tar.gz/${SCAFFOLD_REF}"
    echo "Downloading scaffold from ${SCAFFOLD_REPO}@${SCAFFOLD_REF}..."
    if ! curl -fsSL "$TARBALL_URL" | tar xz -C "$_SCAFFOLD_TMPDIR" --strip-components=1; then
        echo "Error: failed to download $TARBALL_URL" >&2
        exit 1
    fi
    SRC="$_SCAFFOLD_TMPDIR"
fi

if [[ ! -d "$SRC/scaffold" ]]; then
    echo "Error: scaffold source missing scaffold/ directory" >&2
    exit 1
fi

# --- Helpers ---
add_only() {
    local src="$1" dst="$2"
    if [[ -e "$dst" ]]; then
        echo "  skip  $dst (exists)"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    [[ "$src" == *.sh ]] && chmod +x "$dst"
    echo "  add   $dst"
}

overwrite() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    [[ "$src" == *.sh ]] && chmod +x "$dst"
    echo "  write $dst"
}

# --- Execute ---

if [[ "$MODE" == "upgrade" ]]; then
    echo "Upgrade mode: re-copying hooks/ only..."
    if [[ ! -d .claude ]]; then
        echo "Error: .claude/ does not exist. Run without --upgrade first." >&2
        exit 1
    fi
    while IFS= read -r -d '' f; do
        rel="${f#$SRC/scaffold/hooks/}"
        overwrite "$f" ".claude/hooks/$rel"
    done < <(find "$SRC/scaffold/hooks" -type f -print0)
    echo
    echo "Upgrade complete. Skills, CLAUDE.md, and settings.json untouched."
    exit 0
fi

# Install mode
echo "Installing scaffold (non-destructive)..."
mkdir -p .claude

# Walk scaffold/, skipping settings.json (handled after)
while IFS= read -r -d '' f; do
    rel="${f#$SRC/scaffold/}"
    if [[ "$rel" == "settings.json" ]]; then continue; fi
    add_only "$f" ".claude/$rel"
done < <(find "$SRC/scaffold" -type f -print0)

# settings.json: special handling — baseline sidecar if conflict
if [[ -f "$SRC/scaffold/settings.json" ]]; then
    if [[ -f .claude/settings.json ]]; then
        if ! cmp -s .claude/settings.json "$SRC/scaffold/settings.json"; then
            cp "$SRC/scaffold/settings.json" .claude/settings.json.scaffold-baseline
            echo "  note  .claude/settings.json exists; baseline written to .claude/settings.json.scaffold-baseline"
        else
            echo "  skip  .claude/settings.json (already matches baseline)"
        fi
    else
        cp "$SRC/scaffold/settings.json" .claude/settings.json
        echo "  add   .claude/settings.json"
    fi
fi

# Templates → project root
if [[ -f "$SRC/templates/CLAUDE.md.tmpl" ]]; then
    if [[ -e CLAUDE.md ]]; then
        echo "  skip  CLAUDE.md (exists)"
    else
        cp "$SRC/templates/CLAUDE.md.tmpl" CLAUDE.md
        echo "  add   CLAUDE.md"
    fi
fi

echo
echo "Install complete. Next steps:"
echo "  1. Open Claude Code in this directory."
echo "  2. Tell it: 'Run the bootstrap skill'"
echo "  3. Review each phase before approving."
echo
echo "To refresh hook implementations later:  bash install.sh --upgrade"
