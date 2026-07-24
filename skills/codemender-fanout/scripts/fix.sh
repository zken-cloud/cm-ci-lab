#!/usr/bin/env bash
# Phase 3 — fan out `cm fix` across the verified vulnerabilities, one patch each.
#   FIX_FANOUT  parallel workers (default 3)
source "$(dirname "$0")/cm-env.sh"
FANOUT="${FIX_FANOUT:-3}"

[ -f "$WORKSPACE/verified.txt" ] || { echo "no verified.txt — run verify.sh first"; exit 0; }
IDS=""; while IFS= read -r l; do [ -n "$l" ] && IDS="$IDS$l"$'\n'; done < <(sort -u "$WORKSPACE/verified.txt")
[ -n "$IDS" ] || { echo "nothing to fix"; exit 0; }
n=$(printf '%s' "$IDS" | grep -c .)
echo "🔧 fixing $n verified finding(s), $FANOUT at a time"
mkdir -p "$WORKSPACE/patches"

export CM_STATE_HOME REPO_DIR WORKSPACE MIN_SEVERITY CM_BASE_PORT SKILL_DIR GOOGLE_APPLICATION_CREDENTIALS
printf '%s' "$IDS" | xargs -P "$FANOUT" -n1 "$(dirname "$0")/_fix-one.sh"

echo "📦 produced $(ls "$WORKSPACE/patches" 2>/dev/null | wc -l | tr -d ' ') patch(es) → $WORKSPACE/patches/"
