#!/usr/bin/env bash
# Shared setup + helpers, sourced by find.sh / verify.sh / fix.sh and the workers.
# bash 3.2 safe (macOS ships 3.2) — no mapfile / flock / wait -n.
set -euo pipefail

export SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# ---- Inputs (override via env) ----------------------------------------------
export REPO_DIR="${REPO_DIR:-$PWD}"                         # git repo to scan/fix
export WORKSPACE="${CM_RUN_DIR:-$REPO_DIR/.cm-fanout}"      # hand-off files
export CM_STATE_HOME="${CM_STATE_HOME:-$WORKSPACE/state}"   # primary ~/.codemender lives here
export MIN_SEVERITY="${MIN_SEVERITY:-CRITICAL}"
export CM_BASE_PORT="${CM_BASE_PORT:-3000}"

# ADC must resolve even when a worker overrides HOME for SQLite isolation.
# Pin it to the invoking user's ADC file (carries quota_project_id after
# `gcloud auth application-default set-quota-project`).
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.config/gcloud/application_default_credentials.json}"

# ---- Preflight ---------------------------------------------------------------
command -v cm  >/dev/null || { echo "❌ cm not on PATH — run $SKILL_DIR/bootstrap-cm.sh" >&2; exit 1; }
command -v jq  >/dev/null || { echo "❌ jq required" >&2; exit 1; }
command -v git >/dev/null || { echo "❌ git required" >&2; exit 1; }
[ -d "$REPO_DIR/.git" ] || { echo "❌ REPO_DIR=$REPO_DIR is not a git repo" >&2; exit 1; }
mkdir -p "$WORKSPACE"

# ---- Helpers -----------------------------------------------------------------

# Run a command inside the OS-appropriate sandbox.
sbx() { "$SKILL_DIR/sandbox-run.sh" "$@"; }

# Create/normalise a cm state home (its own ~/.codemender) with non-interactive config.
init_state() {  # $1 = state home dir
  local h="$1"; mkdir -p "$h/.codemender"
  if [ ! -f "$h/.codemender/config.yaml" ]; then
    HOME="$h" cm init >/dev/null 2>&1 || true
    cat > "$h/.codemender/config.yaml" <<'YAML'
vcs: { type: "git" }
build: { command: "" }
tools: { confirm_execution: false, confirm_writes: false }
YAML
  fi
}

# Finding IDs at/above MIN_SEVERITY with a given status (OPEN, VERIFIED, ...).
finding_ids() {  # $1 = status
  HOME="$CM_STATE_HOME" cm report --format json --status "$1" --severity "$MIN_SEVERITY" 2>/dev/null \
    | jq -r '.[].FindingID'
}

# Deterministic per-finding port so parallel verify/fix don't collide on the
# app's default port — even where the sandbox shares one network stack (macOS).
worker_port() {  # $1 = fid
  local h; h=$(printf '%s' "$1" | cksum | awk '{print $1}')
  echo $(( CM_BASE_PORT + 1 + (h % 999) ))
}

# Build the `-c` context that asks the agent to bind the app to $1. cm is agentic,
# so a natural-language instruction is robust; override CM_CTX_TEMPLATE for a
# structured key if the CLI expects one. Set CM_CTX_TEMPLATE="" to disable -c.
cm_ctx() {  # $1 = port  -> prints context string (empty if disabled)
  if [ "${CM_CTX_TEMPLATE-__unset__}" = "" ]; then return 0; fi
  local tmpl="${CM_CTX_TEMPLATE:-When building and running the target app to reproduce or fix the exploit, bind it to port %PORT% instead of the default ${CM_BASE_PORT}.}"
  printf '%s' "${tmpl//%PORT%/$1}"
}
