#!/usr/bin/env bash
# One fix worker (invoked by fix.sh via xargs). $1 = FindingID.
# Isolation identical to verify; the patch is read on the host after cm returns.
source "$(dirname "$0")/cm-env.sh"
fid="${1:-}"; [ -n "$fid" ] || exit 0

w="$WORKSPACE/w/f-$fid"; rm -rf "$w"; mkdir -p "$w"
cp -a "$CM_STATE_HOME/.codemender" "$w/.codemender"    # private state.db
git clone -q "$REPO_DIR" "$w/repo"                     # independent clone (own .git)

port="$(worker_port "$fid")"
ctx="$(cm_ctx "$port")"
args=(cm fix "$fid" -y)
[ -n "$ctx" ] && args+=(-c "$ctx")

if SBX_WRITE="$w" SBX_CWD="$w/repo" sbx env HOME="$w" PORT="$port" "${args[@]}"; then
  ( cd "$w/repo" && git diff HEAD ) > "$WORKSPACE/patches/$fid.patch"   # host reads the applied change
  if [ -s "$WORKSPACE/patches/$fid.patch" ]; then
    echo "  ✓ $fid patched (port $port)"
  else
    rm -f "$WORKSPACE/patches/$fid.patch"; echo "  ∅ $fid produced no diff"
  fi
else
  echo "  ✗ $fid fix failed (port $port)"
fi
rm -rf "$w"
