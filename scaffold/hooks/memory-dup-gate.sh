#!/usr/bin/env bash
# PreToolUse hook on Write — auto-memory dedup gate.
#
# PURPOSE:
#   Before a NEW auto-memory file is created under
#   ~/.claude/projects/<sanitized-cwd>/memory/, surface existing memory files
#   whose name or description overlaps the proposed filename's keywords — so a
#   fact that belongs in an existing memory updates that file instead of
#   spawning a near-duplicate.
#
# SCOPE / WHEN IT FIRES — only when ALL hold:
#     - tool is Write
#     - target is *.md under a .../.claude/projects/*/memory/ dir (not MEMORY.md)
#     - the target file does NOT already exist (new file, not an edit/overwrite)
#     - >=1 existing memory file overlaps the proposed filename's keywords
#     - no memory-dir file has been Read yet this session (cold-on-memory)
#   If any condition fails it passes through silently (exit 0). In practice this
#   is at most one block per session, only when a genuinely overlapping new
#   memory is about to be written.
#
# OVERRIDE / ESCAPE:
#   Read any file under the memory dir (the flagged file, or MEMORY.md) and the
#   gate opens for the rest of the session — same mechanism as psql-gate.sh,
#   reusing read-tracker.sh's per-session read-log. Re-run the Write afterward.
#   No env-var bypass.
#
# All output must go to stderr; PreToolUse stdout is NOT reliably seen by Claude
# — only a non-zero (exit 2) block with stderr text lands. (Same finding as
# psql-gate.sh.)

if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if [[ -z "${CLAUDE_PROJECT_DIR:-}" ]]; then exit 0; fi

info=$(cat)
tool_name=$(echo "$info" | jq -r '.tool_name // empty')
file_path=$(echo "$info" | jq -r '.tool_input.file_path // empty')
session_id=$(echo "$info" | jq -r '.session_id // empty')

[[ "$tool_name" != "Write" ]] && exit 0
[[ -z "$file_path" ]] && exit 0

# --- Only guard new .md files inside an auto-memory dir (skip the index) ---
case "$file_path" in
    */.claude/projects/*/memory/*.md) ;;
    *) exit 0 ;;
esac
base="$(basename "$file_path")"
[[ "$base" == "MEMORY.md" ]] && exit 0
# Only NEW files — editing/overwriting an existing memory is fine.
[[ -e "$file_path" ]] && exit 0

mem_dir="$(dirname "$file_path")"
[[ -d "$mem_dir" ]] || exit 0

# --- Cold-on-memory check: if THIS memory dir was Read this session, open ---
# session_id is validated against a safe charset before it touches a path (no
# traversal), and the grep is scoped to this exact memory dir rather than a
# bare "/memory/" substring (which could false-warm on unrelated paths).
read_log=""
if [[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
    read_log="$CLAUDE_PROJECT_DIR/.claude/tmp/sessions/$session_id/read-files.log"
fi
if [[ -n "$read_log" && -f "$read_log" ]] && grep -qF "$mem_dir" "$read_log" 2>/dev/null; then
    exit 0
fi

# --- Derive keyword tokens from the proposed filename ---
stem="${base%.md}"
stem="${stem#feedback_}"; stem="${stem#project_}"
stem="${stem#reference_}"; stem="${stem#user_}"
stem="${stem,,}"
# Structural type words (feedback/project/reference/user) are never dedup
# signals — drop them along with generic glue words.
stop=" feedback project reference user your yourself myself means dont when always never with that this from into using also more than have been ours them they "
tokens=()
IFS='_' read -ra _parts <<< "$stem"
for t in "${_parts[@]}"; do
    t="${t//[^a-z0-9]/}"          # alnum only — neutralizes glob/regex metachars
    [[ ${#t} -ge 4 ]] || continue
    [[ "$stop" == *" $t "* ]] && continue
    tokens+=("$t")
done
[[ ${#tokens[@]} -gt 0 ]] || exit 0

# --- Score existing memory files by whole-word token overlap ---
# Whole-word match on space-normalized words (so "board" hits "set_board_size"
# but not "onboarding"). Substring test on normalized words, not regex, so a
# token can never be interpreted as a pattern. A hit in the filename weighs 2
# (strong dedup signal); a hit only in the description *value* weighs 1.
declare -A score
shopt -s nullglob
for f in "$mem_dir"/*.md; do
    bn="$(basename "$f")"
    [[ "$bn" == "MEMORY.md" ]] && continue
    name_lc="${bn%.md}"; name_lc="${name_lc,,}"
    desc_lc="$(grep -m1 -i '^description:' "$f" 2>/dev/null)"
    desc_lc="${desc_lc#*:}"       # drop the "description:" key, keep the value
    desc_lc="${desc_lc,,}"
    name_w=" ${name_lc//[^a-z0-9]/ } "   # space-delimited words for whole-word test
    desc_w=" ${desc_lc//[^a-z0-9]/ } "
    n=0
    for t in "${tokens[@]}"; do
        if [[ "$name_w" == *" $t "* ]]; then
            n=$((n + 2))
        elif [[ "$desc_w" == *" $t "* ]]; then
            n=$((n + 1))
        fi
    done
    [[ $n -gt 0 ]] && score["$f"]=$n
done
[[ ${#score[@]} -gt 0 ]] || exit 0   # nothing overlaps -> genuinely novel, allow

# --- Build the block message: top matches by overlap score ---
matches="$(for f in "${!score[@]}"; do echo "${score[$f]} $(basename "$f")"; done | sort -rn | head -5)"
top="$(echo "$matches" | head -1 | cut -d' ' -f2-)"

{
    echo "[memory-gate] New memory overlaps existing ones — check before creating a duplicate."
    echo
    echo "Proposed: $base"
    echo "Keywords: ${tokens[*]}"
    echo
    echo "Existing memories that overlap (overlap-count  file):"
    echo "$matches" | sed 's/^/  /'
    echo
    echo "Decide: does the fact belong in one of the above (update it), or is it"
    echo "genuinely distinct (then a new file is right)? Open the closest match:"
    echo "  Read $mem_dir/$top"
    echo
    echo "Reading any memory file opens this gate for the rest of the session;"
    echo "then re-run your Write. (Mirrors psql-gate — one nudge per session.)"
} >&2
exit 2
