#!/usr/bin/env bash
#
# verify.sh — STEP 2: verify the highest-severity finding.
#
# This runs CodeMender's FULL verification: it may build and run the target
# app to reproduce the exploit, so it can take several minutes. That is exactly
# why the CI image ships with node/npm and build tools. We do NOT short-circuit
# it — a verified finding is a stronger signal than a raw scan hit.
source "$(dirname "$0")/cm-env.sh"
cd "$REPO_DIR"

FID=$(top_finding_id)
if [[ -z "$FID" ]]; then
  echo "No findings to verify."; exit 0
fi

echo "🔬 cm find verify ${FID}"
cm find verify "${FID}"

echo "── status after verification ─────────────────────────"
cm report
