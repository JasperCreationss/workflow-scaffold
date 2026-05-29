#!/usr/bin/env bash
# Hermetic tests for memory-dup-gate.sh.
# Builds a throwaway memory dir + read-log under a temp CLAUDE_PROJECT_DIR so
# the assertions never depend on the live ~/.claude memories.
#
# Run:  bash .claude/hooks/memory-dup-gate.test.sh
# Exits non-zero on first failure.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/memory-dup-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"
MEM="$TMP/.claude/projects/proj/memory"
mkdir -p "$MEM"

# --- fixtures ---
cat > "$MEM/feedback_always_set_board_size.md" <<'EOF'
---
name: feedback_always_set_board_size
description: On Project board, always set the Size field
---
body
EOF
# "onboarding" must NOT match the token "board" (word-boundary guard)
cat > "$MEM/feedback_resend_email.md" <<'EOF'
---
name: feedback_resend_email
description: User chose Resend API during onboarding
---
body
EOF
cat > "$MEM/MEMORY.md" <<'EOF'
# index
EOF

pass=0; fail=0
mkjson() { jq -nc --arg t "$1" --arg f "$2" --arg s "$3" \
    '{tool_name:$t,tool_input:{file_path:$f},session_id:$s}'; }

# assert_rc <label> <expected-rc> <tool> <file> <session>
assert_rc() {
    local label="$1" exp="$2"; shift 2
    local err; err="$(mktemp)"
    printf '%s' "$(mkjson "$1" "$2" "$3")" | bash "$HOOK" 2>"$err"
    local rc=$?
    LAST_ERR="$(cat "$err")"; rm -f "$err"
    if [[ "$rc" == "$exp" ]]; then
        echo "ok   - $label (exit $rc)"; pass=$((pass + 1))
    else
        echo "FAIL - $label (got $rc, want $exp)"; fail=$((fail + 1))
    fi
}

NEWDUP="$MEM/feedback_decide_board_status_yourself.md"  # new, overlaps "board"

# 1. new + overlapping + cold session -> BLOCK
assert_rc "new overlapping, cold -> block" 2 Write "$NEWDUP" sess-cold
#    ...and the block names the real match but NOT the onboarding false positive
if grep -q "feedback_always_set_board_size" <<<"$LAST_ERR" \
   && ! grep -q "feedback_resend_email" <<<"$LAST_ERR"; then
    echo "ok   - block lists real match, excludes onboarding false-positive"; pass=$((pass + 1))
else
    echo "FAIL - block message contents wrong:"; echo "$LAST_ERR" | sed 's/^/      /'; fail=$((fail + 1))
fi

# 2. same, but a memory file was Read this session -> PASS
mkdir -p "$TMP/.claude/tmp/sessions/sess-warm"
echo "1700000000 $MEM/feedback_always_set_board_size.md" \
    > "$TMP/.claude/tmp/sessions/sess-warm/read-files.log"
assert_rc "new overlapping, warm (mem read) -> pass" 0 Write "$NEWDUP" sess-warm

# 3. editing an existing memory file -> PASS
assert_rc "existing file (edit) -> pass" 0 Write "$MEM/feedback_resend_email.md" sess-cold

# 4. non-memory path -> PASS
assert_rc "non-memory path -> pass" 0 Write "$TMP/src/foo.md" sess-cold

# 5. non-Write tool -> PASS
assert_rc "non-Write tool -> pass" 0 Edit "$NEWDUP" sess-cold

# 6. new memory, no keyword overlap -> PASS
assert_rc "new, no overlap -> pass" 0 Write "$MEM/reference_zzqqx_widget_telemetry.md" sess-cold

# 7. MEMORY.md index -> PASS
assert_rc "MEMORY.md index -> pass" 0 Write "$MEM/MEMORY.md" sess-cold

# 8. the literal frontmatter key "description" must NOT match every file's
#    `description:` line (the key is stripped before matching).
assert_rc "description-key token -> no false positive" 0 \
    Write "$MEM/feedback_product_description_update.md" sess-cold

# 9. a type word ("feedback") in a non-prefix position must NOT mass-match the
#    feedback_*.md namespace (type words are stopworded).
assert_rc "type-word token -> no mass match" 0 \
    Write "$MEM/feedback_no_feedback_loop.md" sess-cold

# 10. a filename with regex/glob metacharacters must be handled safely (tokens
#     sanitized to alnum) and still block on the real "board" overlap.
assert_rc "metachar filename -> safe + still blocks" 2 \
    Write "$MEM/feedback_board*_size.md" sess-cold

# 11. SECURITY: a path-traversal session_id must NOT open the gate. Plant the
#     file a ".." would resolve to ($TMP/.claude/read-files.log) containing the
#     mem dir; charset validation must reject ".." so the gate stays cold/blocks.
#     (Without the validation this would fail-open -> exit 0.)
echo "1700000000 $MEM/anything.md" > "$TMP/.claude/read-files.log"
assert_rc "traversal session_id -> rejected, still blocks" 2 Write "$NEWDUP" ".."

# 12. SUBSTRING SCOPING: a read of an UNRELATED dir whose path contains
#     "$mem_dir" as a substring (e.g. "<mem_dir>_backup/<file>") must NOT warm
#     the gate. The trailing-slash needle in the gate's grep enforces a
#     directory boundary so /memory_backup/ no longer false-warms /memory/.
mkdir -p "$TMP/.claude/tmp/sessions/sess-bkup"
echo "1700000000 ${MEM}_backup/feedback_resend_email.md" \
    > "$TMP/.claude/tmp/sessions/sess-bkup/read-files.log"
assert_rc "sibling-dir substring read -> still blocks" 2 Write "$NEWDUP" sess-bkup

# 13. CAPITALIZED PREFIX: a new memory whose name starts with a capitalized
#     type prefix (Feedback_) must have that prefix stripped before tokens are
#     derived. Without the lowercase-before-strip order, "Feedback" would land
#     as a token after stop-wording fails on it, and the gate's keyword set
#     would be wrong. Block here proves the keyword "board" still surfaces.
assert_rc "capitalized prefix stripped -> still blocks on real overlap" 2 \
    Write "$MEM/Feedback_decide_BOARD_status.md" sess-cold

echo
echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]]
