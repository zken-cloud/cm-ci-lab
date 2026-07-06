#!/usr/bin/env bash
#
# cm-env.sh — shared setup, sourced by find.sh / verify.sh / fix.sh.
#
# CodeMender keeps its state (config, Ed25519 identity, findings SQLite DB,
# session logs, generated patches) under $HOME/.codemender. In this pipeline
# each phase runs as a SEPARATE Cloud Build step — a fresh container — so that
# state would normally be lost between find, verify, and fix.
#
# To persist it we mount a GCS bucket with gcsfuse and point $HOME at a
# per-run folder inside it. `cm init` writes there once; every later step
# re-mounts the same bucket and finds the identity + findings DB already there.
set -euo pipefail

: "${CM_STATE_BUCKET:?set CM_STATE_BUCKET (GCS bucket for CodeMender state)}"
: "${STATE_ID:?set STATE_ID (per-run isolation, e.g. the Cloud Build \$BUILD_ID)}"

export WORKSPACE="${WORKSPACE:-/workspace}"
export REPO_DIR="${REPO_DIR:-$WORKSPACE/repo}"
export HOME="/mnt/cmstate/${STATE_ID}"          # cm writes ~/.codemender here

# --- Mount the state bucket (once per step/container) ------------------------
mkdir -p /mnt/cmstate
if ! mount | grep -q ' /mnt/cmstate '; then
  echo "🗄️  mounting gs://${CM_STATE_BUCKET} at /mnt/cmstate (gcsfuse)"
  gcsfuse --implicit-dirs "${CM_STATE_BUCKET}" /mnt/cmstate
fi
mkdir -p "$HOME"

# --- One-time CodeMender init for this run ----------------------------------
if [[ ! -f "$HOME/.codemender/config.yaml" ]]; then
  echo "⚙️  cm init (state → gs://${CM_STATE_BUCKET}/${STATE_ID})"
  cm init
  # CI-friendly config: git VCS, no interactive prompts, fresh scans.
  cat > "$HOME/.codemender/config.yaml" <<'YAML'
server: {}
scan:
  extensions:
    include: [".ts", ".js"]
    exclude: [".min.js", ".spec.ts", ".test.ts"]
  incremental: false
output:
  format: table
tools:
  confirm_commands: false
  confirm_writes: false
vcs:
  type: git
build:
  command: ""
YAML
fi

# --- Helper: highest-severity finding UUID from `cm report` (empty if none) --
# This is the "grep the results for the next command" glue: parse the findings
# CodeMender stored and hand the top one to verify / fix.
top_finding_id() {
  cm report -f json 2>/dev/null | jq -r '
    (if type=="array" then . else [] end)
    | sort_by({CRITICAL:4, HIGH:3, MEDIUM:2, LOW:1}[(.Severity|ascii_upcase)] // 0)
    | reverse | (.[0].FindingID // "")'
}
