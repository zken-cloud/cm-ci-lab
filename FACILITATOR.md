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
2. **One org-wide read grant** on the image (Step 3) — no per-participant
   service accounts to collect.
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

## Step 3 — Grant image read access **once, org-wide**

Collecting a Cloud Build service account from every participant does not scale
(each of the 100 projects has its own, and a `domain:` grant only covers *user*
accounts, not the `gserviceaccount.com` build SAs). Instead, grant read access
with a **single** binding that every participant's build inherits:

```bash
# One grant covers every participant's Cloud Build service account.
gcloud artifacts repositories add-iam-policy-binding codemender \
  --location="$REGION" \
  --member="allAuthenticatedUsers" \
  --role="roles/artifactregistry.reader"
```

Why this works and how to tighten it:

- `allAuthenticatedUsers` = any authenticated Google identity, which **includes
  every participant's Cloud Build service account** — nothing to collect, and it
  keeps working as more people join.
- The image embeds a **sensitive EAP credential**, so treat the image path as
  need-to-know and **rotate the credential after the cohort** (rebuild + repush
  a new tag, delete the old one).
- If your org enforces **Domain Restricted Sharing** (which blocks
  `allUsers`/`allAuthenticatedUsers`), use one of these instead — still O(1):
  - Grant reader to a **Google Group**, and have everyone run their builds with
    a **single shared build service account** (created in your central project,
    added to the group) via `gcloud builds submit --service-account=...`; or
  - Have all participants run in **one shared build project** — one Cloud Build
    SA, one grant.

---

## Security

- **The image is sensitive.** The CodeMender server endpoint and credential are
  baked into `cm-linux`, so anyone who can pull the image can call the backend.
  Distribute it **only** through this IAM-gated Artifact Registry repo — never a
  public registry, and never commit `cm-linux` to a public repo (it is
  git-ignored in this repository).
- **The web guide is public** (GCS static site behind an HTTPS LB) but contains
  only placeholders — no project IDs, tokens, service-account emails, or keys.

## When CodeMender is GA

Participants can rebuild the image themselves from `container/` with their own
`cm` binary — the Dockerfile is the reproducible recipe, so the whole lab can be
replayed without you.
