#!/usr/bin/env bash
# Run a command in an OS-appropriate sandbox.
#   SBX_WRITE : colon-separated dirs the command may write to (macOS containment)
#   SBX_CWD   : working directory for the command (default: $PWD)
#   SBX_NET   : Linux gVisor network mode — "sandbox" (own netns, default) or "host"
#   SBX_RUNSC_FLAGS : extra flags for `runsc do` (e.g. "--rootless")
# Usage: sandbox-run.sh <cmd> [args...]
set -euo pipefail

: "${SBX_CWD:=$PWD}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Inner launcher: cd into SBX_CWD, then exec the real command (preserves argv).
run_inner=(/bin/bash -c 'cd "$1" && shift && exec "$@"' _ "$SBX_CWD" "$@")

# Escape hatch: run WITHOUT a sandbox (unsupported host, or plumbing tests). Loud on purpose.
if [ "${SBX_DISABLE:-0}" = "1" ]; then
  echo "⚠️  SBX_DISABLE=1 — running UNSANDBOXED: $*" >&2
  exec "${run_inner[@]}"
fi

case "$(uname -s)" in
  Darwin)
    prof="$(mktemp "${TMPDIR:-/tmp}/cm-sbx.XXXXXX")"
    trap 'rm -f "$prof"' EXIT
    cat "$SELF_DIR/cm.sb" > "$prof"
    # Append a write-allow rule for each SBX_WRITE dir (resolved to an absolute path).
    old_ifs="$IFS"; IFS=':'
    for d in ${SBX_WRITE:-}; do
      [ -n "$d" ] || continue
      abs="$(cd "$d" 2>/dev/null && pwd || echo "$d")"
      printf '(allow file-write* (subpath "%s"))\n' "$abs" >> "$prof"
    done
    IFS="$old_ifs"
    exec sandbox-exec -f "$prof" "${run_inner[@]}"
    ;;
  Linux)
    command -v runsc >/dev/null || {
      echo "❌ runsc (gVisor) not on PATH — install gVisor, or run this host's find/verify with a sandbox you trust" >&2
      exit 1; }
    # `runsc do` = quick sandbox over the host FS, no OCI bundle, no Docker.
    # --network/--rootless/--platform are GLOBAL flags — they go BEFORE `do`.
    #   SBX_NET=sandbox → own network namespace per worker, but ONLY as root;
    #   rootless gVisor doesn't support it and falls back to host net (with a
    #   warning). Parallel-safety comes from the per-worker unique port either way.
    # `runsc do` mounts the host read-only with a tmpfs overlay, so writes are
    # ephemeral by default and `-volume` does NOT write through. We need the
    # hand-off files (state.db, verified.txt, patches) on the host, so we disable
    # the overlay with -force-overlay=false. Tradeoff: the sandboxed command gets
    # host write access — gVisor still isolates syscalls (host kernel) and the
    # network; it does not confine writes to a subtree the way the macOS profile
    # does. (For strict FS confinement on Linux, use a full OCI bundle instead.)
    # shellcheck disable=SC2086
    exec runsc --network="${SBX_NET:-host}" ${SBX_RUNSC_FLAGS:-} do -force-overlay=false "${run_inner[@]}"
    ;;
  *)
    echo "❌ unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
