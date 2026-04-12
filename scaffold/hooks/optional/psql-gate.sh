#!/usr/bin/env bash
# PreToolUse hook on Bash — one-shot cold-session nudge for psql.
#
# Fires exactly once per session: blocks the first psql command if no Read
# tool call has been observed yet, with an educational message pointing the
# user at the project's DB documentation. After any Read, the gate opens
# permanently — no per-query friction.
#
# This hook is OPTIONAL. It is installed to .claude/hooks/optional/ and
# activated by the bootstrap meta-skill iff a database is detected in the
# project. To enable manually: move this file from optional/ to .claude/hooks/
# and add a PreToolUse > Bash entry to .claude/settings.json.
#
# All output must go to stderr; stdout is injected into Claude's context.

if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if [[ -z "${CLAUDE_PROJECT_DIR:-}" ]]; then exit 0; fi

info=$(cat)
tool_name=$(echo "$info" | jq -r '.tool_name // empty')
cmd=$(echo "$info" | jq -r '.tool_input.command // empty')
session_id=$(echo "$info" | jq -r '.session_id // empty')

[[ "$tool_name" != "Bash" ]] && exit 0
[[ -z "$cmd" ]] && exit 0

# --- psql invocation detection ---
if ! echo "$cmd" | grep -qE '(^|[[:space:];&|(])psql([[:space:]"'\''-]|$)'; then
    exit 0
fi
if echo "$cmd" | grep -qE '(^|[[:space:];&|(])(man|which|type|whereis|command)[[:space:]]+psql([[:space:]]|$)'; then
    exit 0
fi
if echo "$cmd" | grep -qE '(^|[[:space:];&|(])(sudo[[:space:]]+)?(apt|apt-get|brew|dnf|yum|pacman|zypper|port|pkg|npm|pip|cargo)[[:space:]]'; then
    exit 0
fi
if echo "$cmd" | grep -qE 'psql[[:space:]]+(--version|-V|--help|-\?)([[:space:]]|$)'; then
    exit 0
fi

# --- Cold-session check ---
read_log="$CLAUDE_PROJECT_DIR/.claude/tmp/sessions/$session_id/read-files.log"
if [[ -f "$read_log" && -s "$read_log" ]]; then
    exit 0
fi

cat >&2 <<'MSG'
[psql-gate] Cold session — read project DB documentation before querying.

This is a one-time nudge per session. Read any file (CLAUDE.md, a domain
README, or a SKILL.md) and the gate opens for the rest of the session.

Recommended reads:
  - CLAUDE.md                              (project overview, DB quick reference)
  - .claude/skills/<domain>/SKILL.md       (domain-specific tables and views)
  - Any database/ or schema/ README in this project

Why this exists: column-name guessing loops are expensive. Reading the
schema doc once eliminates the entire failure class.

Retry your command after reading any file.
MSG
exit 2
