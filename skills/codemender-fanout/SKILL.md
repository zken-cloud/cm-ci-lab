---
name: codemender-fanout
description: Run CodeMender (cm) find, verify, and fix across many findings in parallel with per-worker SQLite state isolation, sandboxed per-OS (macOS sandbox-exec, Linux gVisor/runsc). Use when scanning a repo/directory for vulnerabilities and driving verify+fix at scale from Antigravity.
---

# CodeMender fan-out (sandboxed)

Drives the public-preview CodeMender CLI (`cm`) over a whole directory: **find** many
findings, **verify** them in parallel, **fix** the verified ones in parallel — each
parallel worker isolated so the single-writer SQLite state never corrupts, and every
`cm` invocation wrapped in an OS-appropriate sandbox.

Everything runs **locally as you** (Application Default Credentials). There is no CI,
no bucket, and no secret store — this is the laptop path.

## When to use

- You have a git repo checked out and want CodeMender to scan a directory (not one file)
  and then verify/fix at scale.
- You want the `cm verify` / `cm fix` runs (which build & run the target app and execute
  proof-of-concept exploits) contained in a sandbox rather than running loose on the host.

## Prerequisites (check first)

1. **`cm` on PATH.** If missing: `scripts/bootstrap-cm.sh` downloads the right binary for
   this OS/arch into `~/.local/bin`.
2. **Authenticated ADC**, entitled to the preview:
   ```bash
   gcloud auth application-default login <your-account>
   gcloud auth application-default set-quota-project <CM_PROJECT>   # a project entitled to CodeMender
   ```
3. **`git`, `jq`, `unzip`** on PATH; the target is a **git** repo.
4. **Sandbox runtime:**
   - **macOS** — `sandbox-exec` is built in. Nothing to install.
   - **Linux** — gVisor `runsc` on PATH (`runsc do` mode, no Docker). On an unprivileged
     laptop set `SBX_RUNSC_FLAGS=--rootless` (works with the `systrap` platform — no KVM
     needed). Install: `curl -fsSL https://storage.googleapis.com/gvisor/releases/release/latest/$(uname -m)/runsc -o runsc && chmod +x runsc && sudo mv runsc /usr/local/bin/`.

## Quickstart

Point at the repo and a scan path, then run the three phases in order. Each script reads
its inputs from environment variables.

```bash
SKILL=~/.gemini/config/skills/codemender-fanout/scripts   # or your install path

export REPO_DIR="$PWD"          # git repo to scan/fix (default: cwd)
export SCAN_PATH="routes/"      # a directory OR space-separated files, relative to REPO_DIR
export MIN_SEVERITY=CRITICAL    # floor for which findings flow through verify/fix

"$SKILL/find.sh"                # cm find over SCAN_PATH -> findings in local state.db
"$SKILL/verify.sh"             # fan out cm verify across found vulns  -> verified.txt
"$SKILL/fix.sh"                # fan out cm fix across verified vulns   -> patches/*.patch
```

Outputs land under `$REPO_DIR/.cm-fanout/` (override with `CM_RUN_DIR`):
`state/` (the shared `~/.codemender` used by find), `cm-report.md`, `verified.txt`,
and `patches/<FindingID>.patch`. Apply patches yourself and open a PR — you are the human
in the loop.

## How the fan-out stays safe (SQLite isolation)

`cm` keeps findings in a **single-writer SQLite** `state.db` under `~/.codemender`. `find`
writes it once (serial). `verify`/`fix` then fan out, and **each worker**:

1. **copies** `state/.codemender` to a private per-worker dir and runs with `HOME` pointed
   there — so no two `cm` processes ever write the same SQLite file, and
2. runs in an **independent `git clone`** of the repo (its own `.git`) — a `git worktree`
   shares `.git` and parallel `cm` resets deadlock on `.git/index.lock`.

Results come back through tiny append-only hand-off files (`verified.txt`, `patches/`),
not by writing the shared DB concurrently. Verified/fixed findings are selected by status
via `cm report --format json --status … --severity …`.

### Unique port per worker (so verify/fix parallelise on any OS)

`cm verify`/`cm fix` build and run the target app to reproduce/refix the exploit, on a
fixed default port (3000) — so two workers on one network stack would collide. Instead of
relying on network-namespace isolation, each worker computes a **deterministic unique
port** from the FindingID and passes it to `cm` via **`-c` context** (cm is agentic, so a
plain-language instruction to bind that port is robust) plus a `PORT` env var. This removes
the collision on **macOS too** (where `sandbox-exec` shares the host network), so fan-out
defaults to 3 on both OSes. Override the exact instruction with `CM_CTX_TEMPLATE` (use
`%PORT%` as the placeholder), or set `CM_CTX_TEMPLATE=""` to disable `-c` entirely.

## Sandbox model (per OS)

`sandbox-run.sh` wraps every `cm` call. Contract: `SBX_WRITE=dir1:dir2 SBX_CWD=dir sandbox-run.sh <cmd…>`.

- **macOS — `sandbox-exec`.** A generated profile (`cm.sb` + appended `(allow file-write*
  (subpath …))` for the worker dir) permits reads/exec/network everywhere but **confines
  writes** to the worker dir + tmp. Coarse and deprecated, but ships on every Mac. It does
  **not** isolate the network — but the per-worker unique port (above) means parallel
  verify/fix don't collide anyway, so fan-out still defaults to **3**.
- **Linux — gVisor `runsc do`** (no Docker, no OCI bundle). Each `cm` runs in a gVisor
  sandbox: **syscalls are intercepted, protecting the host kernel** from the exploit/build
  code. Verified working rootless (`SBX_RUNSC_FLAGS=--rootless`, `systrap` platform — no KVM
  needed). Two caveats found by testing:
  - `runsc do` mounts the host **read-only under a tmpfs overlay**, and `-volume` does not
    write through — so the wrapper runs with **`-force-overlay=false`** so the hand-off files
    (state.db, verified.txt, patches) reach the host. This means gVisor here isolates
    **syscalls + network** but does **not** confine filesystem writes to a subtree the way
    the macOS profile does (a compromised `cm` could write the host FS). For strict FS
    confinement on Linux, graduate to a full OCI bundle.
  - **`--network=sandbox` (per-worker netns) needs root** — rootless gVisor falls back to
    host networking. So netns isolation is a **root-only** hardening bonus; default is
    `SBX_NET=host`. Parallel-safety does **not** depend on it — the **per-worker unique port**
    is what prevents collisions on both OSes.

Both sandboxes **allow egress** (cm needs `aiplatform.googleapis.com` — DNS/TCP verified
through gVisor; verify needs the npm registry + localhost). Egress is not allowlisted —
impractical under `sandbox-exec` / `runsc do`.

## Tuning knobs (env vars)

| Var | Default | Meaning |
|-----|---------|---------|
| `REPO_DIR` | `$PWD` | git repo to scan/fix |
| `SCAN_PATH` | *(required for find)* | directory or space-separated files, relative to `REPO_DIR` |
| `MIN_SEVERITY` | `CRITICAL` | severity floor for verify/fix selection |
| `VERIFY_FANOUT` / `FIX_FANOUT` | `3` | parallel workers |
| `SKIP_EXPLOIT` | `0` | `1` → `cm verify --skip-exploit-verification` (static, no app/port) |
| `CM_BASE_PORT` | `3000` | base for the per-worker unique app port |
| `CM_CTX_TEMPLATE` | *(port instruction)* | `-c` context template; `%PORT%` placeholder; `""` disables `-c` |
| `CM_RUN_DIR` | `$REPO_DIR/.cm-fanout` | where hand-off files live |
| `SBX_NET` | `host` | Linux gVisor network mode. `sandbox` = per-worker netns but **root only** (rootless falls back to host) |
| `SBX_RUNSC_FLAGS` | *(empty)* | extra `runsc do` flags — set `--rootless` on an unprivileged laptop |
| `SBX_DISABLE` | `0` | `1` → run **unsandboxed** (loud warning). Unsupported hosts / plumbing tests only. |

## Troubleshooting

- **`Unsupported agent interaction: codemender-preview`** — your ADC identity/quota project
  isn't entitled to the preview agent. Re-check step 2.
- **Linux: `runsc: permission denied` / no network** — run rootless (`SBX_RUNSC_FLAGS=--rootless`)
  or via sudo; if `--network=sandbox` has no egress on your host, set `SBX_NET=host` (parallel
  verify then collides on the port, so also set `VERIFY_FANOUT=1`).
- **macOS: build writes denied** — ensure `HOME` for the worker resolves inside the work dir
  (it does by default); npm/node caches live under `HOME`, which is a permitted write root.

> **Status: v1.** Validated end-to-end with a stub `cm` on Linux **through real gVisor**
> (`runsc` release-20260721, rootless/systrap): find → parallel verify → parallel fix, with
> per-worker SQLite copies + independent clones + unique ports, and the `verified.txt` /
> `patches/` hand-offs persisting to the host. Still needs a real check: the **macOS
> `sandbox-exec` profile** (couldn't run macOS here) and the **real preview binary** —
> including whether `cm`'s `-c` honours the port instruction (if not, set `CM_CTX_TEMPLATE`
> to the correct form, or `""` to disable, and keep fan-out low). Prefer `find` → a single
> `verify` first, then scale up.
