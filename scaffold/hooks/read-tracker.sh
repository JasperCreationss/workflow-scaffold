#!/usr/bin/env bash
# PostToolUse hook on Read — logs the path of any file Claude reads during
# this session, keyed by session_id. Consumed by other hooks (e.g.
# psql-gate.sh) to verify some context was consulted before running gated
# commands.
#
# All output must go to stderr; stdout from PostToolUse hooks is injected
# into Claude's context.

if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if [[ -z "${CLAUDE_PROJECT_DIR:-}" ]]; then exit 0; fi

info=$(cat)
tool_name=$(echo "$info" | jq -r '.tool_name // empty')
file_path=$(echo "$info" | jq -r '.tool_input.file_path // empty')
session_id=$(echo "$info" | jq -r '.session_id // empty')

[[ "$tool_name" != "Read" ]] && exit 0
[[ -z "$file_path" || -z "$session_id" ]] && exit 0

cache_dir="$CLAUDE_PROJECT_DIR/.claude/tmp/sessions/$session_id"
mkdir -p "$cache_dir" 2>/dev/null || exit 0
echo "$(date +%s) $file_path" >> "$cache_dir/read-files.log"

exit 0
