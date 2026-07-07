#!/usr/bin/env bash
#
# find.sh — STEP 1: scan one file with CodeMender and record the findings.
# State (findings DB) is written to the gcsfuse-mounted bucket so the verify
# and fix steps can read it.
source "$(dirname "$0")/cm-env.sh"

: "${SCAN_PATH:?set SCAN_PATH (file to scan, relative to the repo)}"
cd "$REPO_DIR"

echo "🔍 cm find ${SCAN_PATH}"
cm find "${SCAN_PATH}" -y

echo "── findings ──────────────────────────────────────────"
cm report                                   # human-readable table in the log
cm report -f json > "$WORKSPACE/cm-findings.json" || echo 'null' > "$WORKSPACE/cm-findings.json"

FID=$(top_finding_id)
if [[ -z "$FID" ]]; then
  echo "No findings at or above ${MIN_SEVERITY:-CRITICAL} — the verify/fix steps will no-op."
else
  echo "Top finding (>= ${MIN_SEVERITY:-CRITICAL}) selected for verify/fix: $FID"
fi
