#!/usr/bin/env bash
# Phase 1 — scan many files/dirs, recording every finding in the local state.db.
#   REPO_DIR   git repo (default: cwd)
#   SCAN_PATH  a directory OR space-separated files, relative to REPO_DIR  (required)
source "$(dirname "$0")/cm-env.sh"
: "${SCAN_PATH:?set SCAN_PATH to a directory or space-separated files under REPO_DIR}"

init_state "$CM_STATE_HOME"
cd "$REPO_DIR"
for p in $SCAN_PATH; do
  [ -e "$p" ] || { echo "❌ scan target '$p' not found under $REPO_DIR" >&2; ls; exit 1; }
done

echo "🔍 cm find over: $SCAN_PATH"
for p in $SCAN_PATH; do
  echo "  → $p"
  SBX_WRITE="$CM_STATE_HOME" SBX_CWD="$REPO_DIR" \
    sbx env HOME="$CM_STATE_HOME" cm find "$p" -y --bypass-warning
done

HOME="$CM_STATE_HOME" cm report
HOME="$CM_STATE_HOME" cm report --format md > "$WORKSPACE/cm-report.md" 2>/dev/null || true
echo "found $(finding_ids OPEN | wc -l | tr -d ' ') finding(s) at/above $MIN_SEVERITY → $WORKSPACE"
