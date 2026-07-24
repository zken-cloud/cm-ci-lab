#!/usr/bin/env bash
# Phase 2 — fan out `cm verify` across the found (OPEN) vulnerabilities.
# Each worker isolates SQLite state + git clone and runs the app on its own port,
# so verify can parallelise on either OS.
#   VERIFY_FANOUT  parallel workers (default 3)
#   SKIP_EXPLOIT   1 -> static verify only (no app, no port)
source "$(dirname "$0")/cm-env.sh"
FANOUT="${VERIFY_FANOUT:-3}"
export SKIP_EXPLOIT="${SKIP_EXPLOIT:-0}"

IDS=""; while IFS= read -r l; do [ -n "$l" ] && IDS="$IDS$l"$'\n'; done < <(finding_ids OPEN)
[ -n "$IDS" ] || { echo "nothing to verify"; exit 0; }
n=$(printf '%s' "$IDS" | grep -c .)
echo "🧪 verifying $n finding(s), $FANOUT at a time (skip_exploit=$SKIP_EXPLOIT)"
: > "$WORKSPACE/verified.txt"

export CM_STATE_HOME REPO_DIR WORKSPACE MIN_SEVERITY CM_BASE_PORT SKILL_DIR GOOGLE_APPLICATION_CREDENTIALS
printf '%s' "$IDS" | xargs -P "$FANOUT" -n1 "$(dirname "$0")/_verify-one.sh"

echo "✅ verified $(wc -l < "$WORKSPACE/verified.txt" | tr -d ' ') finding(s) → $WORKSPACE/verified.txt"
