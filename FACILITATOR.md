# CodeMender CI Lab — Facilitator Guide

> **Not for participants.** This covers the one-time setup only the lab owner
> does: building and publishing the CodeMender image, and granting each
> participant access. Participants use the web guide at
> **https://cm-ci-lab.cedemo.app** and never see this file.

You do this **once** (or once per image version). Participants then build
everything else themselves in their own GCP projects and GitHub accounts.

> **EAP note.** This CodeMender build is Early Access. The image bakes in an EAP
> server credential (hence "sensitive" below), and the participant scripts work
> around a few current gaps (e.g. `cm fix --export` is unimplemented). See the
> guide's *Production hardening & EAP caveats* section and `README.md` for the
> full list — worth mentioning to participants up front.

**See also:** repo overview and architecture in [`README.md`](README.md);
participant guide at **https://cm-ci-lab.cedemo.app**.

---

## What you provide to participants

1. The **CodeMender image URL** (from Step 2 below).
2. **Read access on the image** for each participant's Cloud Build service
   account(s) (Step 3) — collect their project number, grant both SA variants.
3. The lab URL: **https://cm-ci-lab.cedemo.app**

That's it. Everything else — state bucket, tokens, scripts, pipeline — is the
participant's own work in the guide.

---

## Prerequisites

- The `cm-linux` binary (you have it; participants do not).
- `gcloud` authenticated with rights to a **central** GCP project that will host
  the image.
- No local Docker needed — Cloud Build builds the image.

---

## The image

A deliberately **minimal toolbox**: the `cm` binary plus the tools the pipeline
needs — node/npm (so `cm find verify` can build & run Juice Shop to reproduce an
exploit), git, jq, and gcsfuse (for GCS-backed state). It bakes in **no**
orchestration; participants write the find/verify/fix scripts themselves.

The build recipe is `container/Dockerfile` and `container/cloudbuild.image.yaml`
in this repo.

---

## Who administers the image

Repo administration is managed through a Google Group, not per-person bindings.
A facilitator admin group (`cm-ci-lab-admin@<YOUR_ORG_DOMAIN>`) holds
`roles/artifactregistry.admin` on the `codemender` repo (in the central project),
so every facilitator in it can pull, push, delete, and manage IAM on the image.
Add or remove a facilitator by changing group membership — no IAM edit needed.

> Because the baked credential is extractable and cannot be rotated (see
> **Security**), admin = ability to overwrite/delete the only copy of the image.
> Keep membership to trusted facilitators.

---

## Step 1 — Enable APIs & create the repository

```bash
export CENTRAL_PROJECT=your-central-project
export REGION=us-central1
gcloud config set project "$CENTRAL_PROJECT"
gcloud services enable artifactregistry.googleapis.com cloudbuild.googleapis.com

gcloud artifacts repositories create codemender \
  --repository-format=docker --location="$REGION" \
  --description="CodeMender CI toolbox image"
```

## Step 2 — Build & push the image

```bash
cp cm-linux container/cm-linux                      # put the binary in the build context

gcloud builds submit container/ \
  --config container/cloudbuild.image.yaml \
  --substitutions=_LOCATION="$REGION",_REPO=codemender,_IMAGE=codemender-ci,_TAG=v0.2.0
```

Share this URL with participants (it goes in their `_CM_IMAGE` substitution):

```
$REGION-docker.pkg.dev/$CENTRAL_PROJECT/codemender/codemender-ci:v0.2.0
```

## Step 3 — Grant image read access per participant

The image is pulled **inside Cloud Build**, so it is pulled by each participant's
**Cloud Build service account**, never by the person (they can't `docker pull` on
their laptops). Grant reader to that SA. Because the image embeds a **sensitive
EAP credential**, the default here is the **tight, per-participant grant** —
scoped to exactly the SAs that need it — rather than a broad org-wide binding.

You need each participant's **project number** — the two build-SA emails are
fully derivable from it (`PROJNUM@cloudbuild…` and `PROJNUM-compute@developer…`),
so you collect one short number, not two long emails.

### 3a — Share a Google Sheet for participants to submit to

Create a Google Sheet and share it with the cohort — **the participant guide's
Step 6 tells them to paste their project number into it**, so put its link there.
Ask for one column, **"GCP project number"** (name/email optional for tracking),
and include this retrieval command in the header note so nobody submits a project
*ID* by mistake:

```bash
gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)'
```

The sheet is your single source of truth and pairs with the idempotent loop below
so you can re-drain it as rows arrive. (A Google **Form** that feeds the sheet is
cleaner at scale — participants can't see or overwrite each other's rows.)

### 3b — Extract the submissions and grant both build SAs

Pull the project-number column out of the sheet into `project-numbers.txt`, one
number per line (File → Download → **CSV**, then keep that column — or just copy
the column). Then run the grant loop below. `add-iam-policy-binding` is
**idempotent** (re-adding a member is a no-op), so you can run it repeatedly —
even on a `watch` during the lab — as new rows arrive, without tracking who's
already done:

```bash
# project-numbers.txt: one project NUMBER per line
while read -r PROJNUM; do
  PROJNUM="${PROJNUM//[^0-9]/}"; [[ -z "$PROJNUM" ]] && continue   # skip blanks/IDs
  for SA in "${PROJNUM}@cloudbuild.gserviceaccount.com" \
            "${PROJNUM}-compute@developer.gserviceaccount.com"; do
    gcloud artifacts repositories add-iam-policy-binding codemender \
      --location="$REGION" --project="$CENTRAL_PROJECT" \
      --member="serviceAccount:${SA}" --role="roles/artifactregistry.reader"
  done
done < project-numbers.txt
```

- Grant **both** SAs. A project builds as the legacy `@cloudbuild` SA *or* the
  default `-compute@developer` SA; if you grant only one and the build uses the
  other, the image pull fails with `denied` (the log shows which SA it used).
- **Revoke after the cohort.** Because the baked key is extractable from the
  image and you cannot rotate it yourself (see Security), the real post-lab
  mitigation is to **remove these grants** — swap `add-iam-policy-binding` for
  `remove-iam-policy-binding` in the loop.
- *Optional automation:* an Apps Script / Cloud Function on form-submit could
  apply the grant itself, but that needs a standing SA with
  `artifactregistry.admin` on the repo — more attack surface than a one-off lab
  warrants. Prefer the manual idempotent loop.

**Fallback — `allAuthenticatedUsers` (avoid unless you must).** A single broad
grant covers every build SA with nothing to collect — but the baked key is a
**Google API key extractable from the image with `strings`**, and you **can't
rotate it** (only the CM team can). So this grant effectively publishes a live,
unrotatable credential to the entire authenticated internet. Use only if
collecting numbers is truly impossible, and time-box it with an IAM Condition:

```bash
gcloud artifacts repositories add-iam-policy-binding codemender \
  --location="$REGION" --member="allAuthenticatedUsers" \
  --role="roles/artifactregistry.reader" \
  --condition='expression=request.time < timestamp("2026-01-01T00:00:00Z"),title=lab-day-only'
```

If Domain Restricted Sharing blocks `allAuthenticatedUsers` too, run all builds
in **one shared build project** (one SA, one grant) — but note that
re-centralizes each participant's GitHub token and Cloud Build quota, so it's
worse than per-SA at scale.

---

## Security

- **The image is sensitive — and irreducibly so.** The CodeMender API key is a
  Google API key baked into `cm-linux` at build time (a `-X …config.bakedAPIKey`
  ldflag). It is **extractable from the image in one command**
  (`strings /usr/local/bin/cm | grep AIza`) and sent as the `x-goog-api-key`
  header, so anyone who can pull the image can call the CM backend *directly*,
  image or not. There is **no runtime override** (config exposes only
  `server.endpoint`, no `api_key` field), and **you cannot rotate the key
  yourself** — re-keying requires Google's internal `build_cm.sh`. So access
  control is the *only* protection: distribute the image **only** through this
  IAM-gated repo, scope pulls to the collected build SAs, **revoke after the
  cohort**, and never commit `cm-linux` to a public repo (it is git-ignored
  here). To make the image non-sensitive, ask the CM team for a build that reads
  the key at **runtime** (env / Secret Manager) or issues short-lived keys.
- **The web guide is public** (GCS static site behind an HTTPS LB) but contains
  only placeholders — no project IDs, tokens, service-account emails, or keys.

## When CodeMender is GA

Participants can rebuild the image themselves from `container/` with their own
`cm` binary — the Dockerfile is the reproducible recipe, so the whole lab can be
replayed without you.
