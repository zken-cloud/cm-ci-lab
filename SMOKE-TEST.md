# CodeMender Smoke Test

Run CodeMender on your own machine first — download the CLI, scan OWASP Juice Shop, verify a real vulnerability, and generate the fix. Ten minutes, no CI. Once this works for you, automate it with [GitHub Actions](https://cm-ci-lab.cedemo.app/gha).

**⏱ ~10 min · ☁ @google.com · cloud-llm-preview1 · 🖥️ your laptop**

> **✓ This is the verified path.** Everything here has been run for real with a `@google.com` identity against `cloud-llm-preview1`. If a step fails, fix it here before touching CI — the pipelines just wrap these same commands.

---

## 1. Download the CLI

**Pick your OS** (most run this on a Mac). The binary carries **no credential** — it authenticates as you.

**macOS · Apple silicon**
```bash
gcloud artifacts generic download --project=cmoc-prod --location=us \
  --repository=codemender-cli-production --package=cm --version=stable \
  --name=cm-darwin-arm64.zip --destination=./
unzip cm-darwin-arm64.zip && chmod +x cm && mv cm /usr/local/bin/cm
```

**macOS · Intel**
```bash
gcloud artifacts generic download --project=cmoc-prod --location=us \
  --repository=codemender-cli-production --package=cm --version=stable \
  --name=cm-darwin-amd64.zip --destination=./
unzip cm-darwin-amd64.zip && chmod +x cm && mv cm /usr/local/bin/cm
```

**Linux x86_64**
```bash
gcloud artifacts generic download --project=cmoc-prod --location=us \
  --repository=codemender-cli-production --package=cm --version=stable \
  --name=cm-linux-amd64.zip --destination=./
unzip cm-linux-amd64.zip && chmod +x cm && sudo mv cm /usr/local/bin/cm
```

**Linux ARM64**
```bash
gcloud artifacts generic download --project=cmoc-prod --location=us \
  --repository=codemender-cli-production --package=cm --version=stable \
  --name=cm-linux-arm64.zip --destination=./
unzip cm-linux-arm64.zip && chmod +x cm && sudo mv cm /usr/local/bin/cm
```

Windows builds exist too (`cm-windows-amd64.zip` / `-arm64`) — install via PowerShell's `Expand-Archive` and add `cm.exe` to your PATH.

---

## 2. Authenticate & init

Sign in as your `@google.com` identity and bill CodeMender to the entitled project.

```bash
gcloud auth application-default login <ldap>@google.com
gcloud auth application-default set-quota-project cloud-llm-preview1

cm init            # creates ~/.codemender state files
cm init --verify   # checks config & backend connectivity
```

**Point CodeMender at git.** Add a `vcs` block to your config so `cm verify`, `cm fix`, and `cm vcs` can read your working tree:

```yaml
# ~/.codemender/config.yaml
vcs:
  type: git
  commands:
    diff: "git diff"
    status: "git status"
```

Without this, `cm vcs status` / `cm vcs diff` in Step 6 have no VCS backend to call.

> **⚠ If you see `Unsupported agent interaction` later.** Your identity or quota project isn't entitled to the preview agent. Confirm you signed in as `@google.com` and the quota project is `cloud-llm-preview1`, then ask the facilitator.

---

## 3. Clone Juice Shop

```bash
cd /tmp && rm -rf juice-shop
git clone --depth 1 https://github.com/juice-shop/juice-shop
cd juice-shop
```

OWASP Juice Shop is intentionally vulnerable — the perfect target to see CodeMender find and fix something real.

---

## 4. Find

Scan the login route. CodeMender streams only snippets to the backend; the reasoning runs in the cloud.

```bash
cm find routes/login.ts -y --bypass-warning
cm report
```

> **✓ Expect 1 CRITICAL SQL Injection.** Grab the finding id from `cm report` (or `cm report --format json | jq -r '.[0].FindingID'`) — you'll pass it to verify and fix.

---

## 5. Verify

Ask CodeMender to *prove* it's exploitable — it builds and runs Juice Shop and fires a proof-of-concept exploit.

```bash
FID="$(cm report --format json | jq -r '.[0].FindingID')"
cm verify "$FID" -y
```

This is the long pole (a few minutes — it runs the app).

> **⚡ Faster static-only pass.** Skip the exploit build/run for a quick static check — don't forget the `-y`:
> ```bash
> cm verify "$FID" --skip-exploit-verification -y
> ```

---

## 6. Fix

Generate and apply the patch, then read the diff — you're the human in the loop.

```bash
cm fix "$FID" -y      # patches, rebuilds, re-runs the exploit
cm vcs status
cm vcs diff           # the parameterized-query fix
```

> **✓ That's the whole loop.** find → verify → fix, running as you, billed to `cloud-llm-preview1`. The CI labs automate exactly this.

---

## Automate it in CI

Now wrap these commands in a pipeline that clones a fork, runs find/verify/fix, and opens a PR you review and merge:

- **[GitHub Actions](https://cm-ci-lab.cedemo.app/gha)** — Qwiklab.

---

*CodeMender Smoke Test · public preview. Juice Shop is © OWASP, MIT-licensed, and intentionally vulnerable — for lab use only. No secrets appear here; `cm` authenticates as your own `@google.com` identity via Application Default Credentials.*
