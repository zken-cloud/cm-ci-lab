# CodeMender CI Lab

A hands-on, **guided** lab that teaches cloud security engineers to run
**CodeMender** (`cm`) as a Cloud Build pipeline: scan OWASP **Juice Shop**,
**verify** a real vulnerability, generate & apply the **fix**, and open a Pull
Request on the participant's own GitHub fork — with a human approving the merge.

Participants don't get a magic image that does everything — they **build the
container, set up GCS-backed state, and hand-write the orchestration scripts and
the Cloud Build pipeline** themselves, step by step.

- **Participant guide (public):** https://cm-ci-lab.cedemo.app
- **Facilitator guide (one-time image build & publish):** [`FACILITATOR.md`](FACILITATOR.md)

> **Note:** This CodeMender build is **Early Access (EAP)**. A couple of rough
> edges are worked around in the scripts (see *Notes & gotchas* below and the
> guide's *Production hardening & EAP caveats* section) and should smooth out as
> the product matures.

---

## Layout

```
cm-ci-lab/
├── cm-linux                         # CodeMender client binary (you provide; git-ignored)
├── container/                       # ── the minimal CodeMender toolbox image ──
│   ├── Dockerfile                   #    cm + node/npm + build-essential + git/jq + gcsfuse
│   ├── cloudbuild.image.yaml        #    build & push the image via Cloud Build
│   └── .dockerignore
├── pipeline/                        # ── reference copy of what participants author ──
│   ├── cloudbuild.yaml              #    clone → find → verify → fix → open-pr (separate steps)
│   └── scripts/
│       ├── cm-env.sh                #    gcsfuse-mount state + cm init + top_finding_id parser
│       ├── find.sh                  #    cm find  → record findings
│       ├── verify.sh                #    cm find verify  (full reproduction, not skipped)
│       ├── fix.sh                   #    cm fix  → apply stored patch deterministically
│       └── open-pr.sh               #    commit → push branch → open GitHub PR
└── webapp/
    └── index.html                   # the step-by-step lab guide (open in a browser / host)
```

`webapp/index.html` is generated from the real script files, so the guide never
drifts from what runs. The `pipeline/` tree is the reference implementation the
guide walks participants through creating.

## Roles

| Role | Does | Where |
|---|---|---|
| **Facilitator** | Build & publish the CodeMender image once; grant each participant's Cloud Build SA read access | Central GCP project |
| **Participant** | Fork Juice Shop, create state bucket, write scripts + pipeline, run it, review & merge the PR | Own GCP project + GitHub |

---

## Facilitator quickstart

The one-time image build & publish, and per-participant access grants, live in
their own doc: **[`FACILITATOR.md`](FACILITATOR.md)**. In short: build
`container/` into Artifact Registry as `codemender-ci:v0.2.0`, share the image
URL, and grant image read to **each participant's two Cloud Build service
accounts** — collect their project *number* and grant both SA variants on the
repo (see `FACILITATOR.md`). The image embeds a **sensitive EAP credential**, so
this stays a tight, per-SA grant. Note an org-wide `domain:` grant is *not* an
option: `domain:` matches user accounts, not service accounts — and the pipeline
pulls as the build SA. Then send them the guide at https://cm-ci-lab.cedemo.app.

---

## Architecture

Five Cloud Build steps run in the participant's project:

1. **clone** — shallow-clone the fork into `/workspace/repo`.
2. **find** (`scripts/find.sh`) — `cm find <path>`; records findings.
3. **verify** (`scripts/verify.sh`) — `cm find verify` runs CodeMender's **full**
   verification (it may build & run Juice Shop to reproduce the exploit — the
   reason the image ships node/npm). Not short-circuited.
4. **fix** (`scripts/fix.sh`) — `cm fix`, then apply CodeMender's stored patch
   from `cm report --patches` **deterministically**.
5. **open-pr** (`scripts/open-pr.sh`) — commit, push the branch with the `gh-pat`
   secret, open a PR whose body is CodeMender's analysis.

### State management (GCS + gcsfuse)
Each step is a fresh container, so CodeMender's `~/.codemender` (config, Ed25519
identity, findings **SQLite** DB) would be lost between steps. `scripts/cm-env.sh`
mounts a **GCS bucket with gcsfuse** and sets `HOME=/mnt/cmstate/$BUILD_ID`, so
`cm init` and the findings persist across find → verify → fix. (Confirmed working
in Cloud Build, including SQLite on the mount.)

### No CodeMender secret
The server endpoint + credential are baked into the `cm` binary, so runtime needs
no CodeMender secret. The only secret is the participant's GitHub token in Secret
Manager.

---

## Notes & gotchas (baked into the scripts)

- **fix determinism** — `cm fix`'s exploit-testing path sometimes resets the tree
  and leaves the patch only *stored*. `fix.sh` therefore resets to HEAD and
  applies the stored patch from `cm report --patches` (`cm fix --export` is not
  implemented).
- **token newline** — tokens from `gh auth token` / Secret Manager carry a
  trailing newline; `open-pr.sh` strips it and redacts the token from logs.
- **Cloud Build SA** — projects use either the legacy
  `PROJECT_NUMBER@cloudbuild.gserviceaccount.com` or the compute SA; the guide
  grants both (secretAccessor + storage.objectAdmin + artifactregistry.reader).
- **scan scope** — because the checkout lives in `/workspace` (not `/tmp`), a
  single-file scan target keeps CodeMender's sandbox scoped to that file.

## Production hardening & EAP caveats

The lab is intentionally transparent (bash + `cm` CLI) so engineers see every step.
This CodeMender build is **Early Access**; some scripting exists only to work
around current gaps, and the guide surfaces both to participants (see its
*Production hardening & EAP caveats* section).

**EAP gaps worked around today** (expect these to disappear):
- `cm fix --export` is unimplemented and the fix agent can reset the tree →
  `fix.sh` re-applies the stored patch from `cm report --patches`.
- Verification builds & runs the whole app (~10–15 min) → the long pole.
- Exit codes aren't yet reliable → scripts re-read `cm report` between phases.

**Best practices for a real deployment:**
- Emit `cm report -f sarif` into **Security Command Center** or **GitHub code
  scanning** instead of ad-hoc `jq` parsing.
- Use a **Cloud Build trigger** on the fork (auto-checkout, runs on push/PR)
  instead of manual `gcloud builds submit`.
- Set `build.command` so `cm build` rejects patches that don't compile/test.
- Pin the image by **digest**, least-privilege SAs, rotate/scope the GitHub
  token (fine-grained PAT or GitHub App), consider Workload Identity Federation.
- Replace the bash glue with a small typed orchestrator (Python) for retries and
  structured errors once you outgrow the lab; widen scans to directories.

## Security

- **The image is sensitive** (it can call the CodeMender backend). Distribute it
  only via the IAM-gated Artifact Registry repo; never commit `cm-linux` publicly.
- **No secrets in the guide** — placeholders only.

## When CodeMender is GA
Participants can rebuild the image from `container/` with their own `cm` binary —
the Dockerfile is the reproducible recipe.

## Hosting the guide (Cloud Run + HTTPS LB + IAP)

`webapp/` is an **nginx container on Cloud Run**, fronted by an external HTTPS Load
Balancer and gated by **IAP** (all paths require Google sign-in), in project
`<PROJECT_ID>`. It contains only placeholders — no secrets.

- **URL:** https://cm-ci-lab.cedemo.app — the Cloud Build guide.
  **`/gha`** — the GitHub Actions variant (staged; see `webapp/nginx.conf.template` routing).
- **Cloud Run:** service `cm-lab-site` (region `us-central1`), nginx serving
  `webapp/index.html` at `/` and `webapp/gha/index.html` at `/gha`.
- **LB:** serverless NEG `cm-lab-neg` → backend-service `cm-lab-run-backend`
  (**IAP enabled**) → url-map `cm-lab-urlmap` → https-proxy `cm-lab-https-proxy`
  (managed cert `cm-lab-cert-cedemo`) → forwarding rule `cm-lab-https-fr`;
  HTTP `cm-lab-http-fr` redirects to HTTPS.
- **Token gate:** on top of IAP, nginx requires a shared access token
  (`?token=…` once, then a cookie). The value is **not in the repo** — it is read
  from the `SITE_TOKEN` env var at container start (`envsubst` renders
  `webapp/nginx.conf.template`), and the container refuses to start without it.

Deploy after editing `webapp/` (builds the Dockerfile via Cloud Build, rolls out a
new revision — traffic switches automatically):
```bash
gcloud run deploy cm-lab-site --source webapp/ \
  --region us-central1 --project <PROJECT_ID> \
  --set-env-vars SITE_TOKEN=<SITE_TOKEN>
```

## Validation
Built and validated end-to-end in project `<PROJECT_ID>`: image published to
Artifact Registry, full pipeline run opened a real PR on a Juice Shop fork with
the correct parameterized-query fix; CodeMender state persisted in GCS across the
separate steps; guide served over HTTPS at the URL above.

## License

Apache-2.0 — see [`LICENSE`](LICENSE). OWASP Juice Shop (the scan target) is
MIT-licensed and is fetched separately at run time; it is not vendored here.
