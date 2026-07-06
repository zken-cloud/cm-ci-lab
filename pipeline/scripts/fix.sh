#!/usr/bin/env bash
#
# fix.sh — STEP 3: generate the fix for the highest-severity finding, then apply
# CodeMender's stored patch deterministically and leave metadata for open-pr.
source "$(dirname "$0")/cm-env.sh"
cd "$REPO_DIR"

FID=$(top_finding_id)
if [[ -z "$FID" ]]; then
  echo "No findings to fix."; echo "NONE" > "$WORKSPACE/cm-status.txt"; exit 0
fi

# Grab finding metadata for the PR body NOW (before cm fix touches the tree).
cm report -f json | jq --arg id "$FID" '.[]|select(.FindingID==$id)' > "$WORKSPACE/cm-finding.json"
STATUS=$(jq -r '.Status' "$WORKSPACE/cm-finding.json")
FILE=$(jq -r '.FilePath' "$WORKSPACE/cm-finding.json" | sed "s#^$REPO_DIR/##")
if [[ "$STATUS" == "DISMISSED" ]]; then
  echo "Finding $FID was DISMISSED during verification — not fixing."
  echo "DISMISSED" > "$WORKSPACE/cm-status.txt"; exit 0
fi

echo "🩹 cm fix ${FID} --auto-apply -y"
cm fix "${FID}" --auto-apply -y 2>&1 | tee "$WORKSPACE/cm-fix.out"

# CodeMender prints a one-line headline tagged [Summary]; capture the last one.
SUMMARY=$(grep -aoE '\[Summary\][[:space:]]+.*' "$WORKSPACE/cm-fix.out" | tail -1 | sed -E 's/^\[Summary\][[:space:]]+//')
[[ -z "$SUMMARY" ]] && SUMMARY="Applied CodeMender remediation for finding ${FID}."
printf '%s\n' "$SUMMARY" > "$WORKSPACE/cm-summary.txt"

# The fix agent may or may not leave its patch applied (it sometimes builds/runs
# the app to test the fix and then resets the tree). To be deterministic we
# reset the tree to HEAD and apply CodeMender's STORED patch as the single
# source of truth, extracted from `cm report --patches`.
git checkout -- . 2>/dev/null || true
rm -rf "$REPO_DIR"/.exploit "$REPO_DIR"/.cm_project "$REPO_DIR"/routes/.exploit 2>/dev/null || true

cm report --patches 2>/dev/null | awk '
  /^  diff --git /{cap=1}
  cap && /^  /{print; next}
  cap && !/^  /{cap=0}
' | sed 's/^  //' > "$WORKSPACE/cm.patch"
sed -i -e :a -e '/^[[:space:]]*$/{$d;N;ba}' "$WORKSPACE/cm.patch"   # trim trailing blanks

if [[ ! -s "$WORKSPACE/cm.patch" ]]; then
  echo "❌ CodeMender produced no patch."; echo "NO_PATCH" > "$WORKSPACE/cm-status.txt"; exit 1
fi
git apply --whitespace=nowarn "$WORKSPACE/cm.patch"

if git diff --quiet -- "$FILE"; then
  echo "❌ patch did not change ${FILE}."; echo "NO_CHANGE" > "$WORKSPACE/cm-status.txt"; exit 1
fi

echo "FIXED" > "$WORKSPACE/cm-status.txt"
echo "✅ Fix applied to ${FILE}"
git --no-pager diff -- "$FILE"
