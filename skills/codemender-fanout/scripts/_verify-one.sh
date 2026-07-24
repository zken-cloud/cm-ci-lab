#!/usr/bin/env bash
# One verify worker (invoked by verify.sh via xargs). $1 = FindingID.
# Isolation: private SQLite state copy + independent git clone + unique app port.
source "$(dirname "$0")/cm-env.sh"
fid="${1:-}"; [ -n "$fid" ] || exit 0

w="$WORKSPACE/w/v-$fid"; rm -rf "$w"; mkdir -p "$w"
cp -a "$CM_STATE_HOME/.codemender" "$w/.codemender"    # private state.db (single-writer)
git clone -q "$REPO_DIR" "$w/repo"                     # independent clone (own .git)

port="$(worker_port "$fid")"
ctx="$(cm_ctx "$port")"
args=(cm verify "$fid" -y)
[ -n "$ctx" ] && args+=(-c "$ctx")
[ "${SKIP_EXPLOIT:-0}" = "1" ] && args+=(--skip-exploit-verification)

if SBX_WRITE="$w" SBX_CWD="$w/repo" sbx env HOME="$w" PORT="$port" "${args[@]}"; then
  echo "$fid" >> "$WORKSPACE/verified.txt"             # O_APPEND, one short line = atomic
  echo "  ✓ $fid verified (port $port)"
else
  echo "  ✗ $fid not verified (port $port)"
fi
rm -rf "$w"
