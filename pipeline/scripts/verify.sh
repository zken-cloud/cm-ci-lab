#!/usr/bin/env bash
#
# verify.sh — STEP 2: verify the highest-severity finding, capped at 15 minutes.
#
# cm find verify runs CodeMender's FULL verification — it may build and run the
# app to reproduce the exploit. That is powerful but VARIABLE: usually a few
# minutes, occasionally 40+ as the agent keeps retrying to stand up the app.
# We cap it so the pipeline always finishes. Hitting the cap does NOT skip the
# fix — we proceed, record the verdict, and the open-pr step flags the PR as
# UNVERIFIED so the human reviewer knows to scrutinise it (human-in-the-loop).
source "$(dirname "$0")/cm-env.sh"
cd "$REPO_DIR"

FID=$(top_finding_id)
if [[ -z "$FID" ]]; then echo "No findings to verify."; exit 0; fi

VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-900}"          # 15 minutes
echo "🔬 cm find verify ${FID}  (capped at ${VERIFY_TIMEOUT}s)"
if timeout "${VERIFY_TIMEOUT}s" cm find verify "${FID}"; then
  echo "✅ verification finished within the cap"
else
  rc=$?
  if [[ $rc -eq 124 ]]; then
    echo "⏱️  verification hit the ${VERIFY_TIMEOUT}s cap — proceeding to fix; the PR will be flagged UNVERIFIED for human review"
    # Cancel any session the cap interrupted so the fix session starts cleanly.
    for s in $(cm session list 2>/dev/null | awk 'NR>2 && /RUNNING/ {print $1}'); do
      cm session cancel "$s" >/dev/null 2>&1 || true
    done
  else
    echo "verify exited ($rc) — proceeding"
  fi
fi

# Record the verdict for the PR body: VERIFIED / DISMISSED / OPEN (=not confirmed).
STATUS=$(cm report -f json | jq -r --arg id "$FID" '.[]|select(.FindingID==$id)|.Status' 2>/dev/null)
echo "${STATUS:-OPEN}" > "$WORKSPACE/cm-verify-status.txt"
echo "── status after verification (verdict: ${STATUS:-OPEN}) ──"
cm report
