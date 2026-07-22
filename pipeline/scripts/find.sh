#!/usr/bin/env bash
#
# find.sh — STEP 1: scan one file with CodeMender and record the findings.
# State (findings DB) is written to the gcsfuse-mounted bucket so the verify
# and fix steps can read it.
source "$(dirname "$0")/cm-env.sh"

: "${SCAN_PATH:?set SCAN_PATH (file to scan, relative to the repo)}"
cd "$REPO_DIR"

# Fail early and legibly on a mistyped _SCAN_PATH. A stray character is easy to
# miss in a long --substitutions line, so print the real directory next to it.
if [[ ! -e "$SCAN_PATH" ]]; then
  echo "❌ SCAN_PATH '${SCAN_PATH}' does not exist in the repo."
  echo "   Check _SCAN_PATH for typos or stray characters. Nearby files:"
  ls -1 "$(dirname "$SCAN_PATH")" 2>/dev/null | head -20 | sed 's/^/     /' || true
  exit 1
fi

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
