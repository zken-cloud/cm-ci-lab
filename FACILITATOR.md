# CodeMender CI Lab — Facilitator Guide

> **Not for participants.** This is for facilitators **delivering** the lab. It
> assumes your **`ldap@gcp.altostrat.com`** identity has been granted access to
> the central GCP project and the `codemender` Artifact Registry repo.
> Participants use the web guide at **https://cm-ci-lab.cedemo.app** and never
> see this file.

> **⚠ Use your `@gcp.altostrat.com` identity — not `@google.com`.** The central
> project lives in **Argolis**, which enforces Domain Restricted Sharing: an
> `@google.com` principal **cannot hold an IAM binding there**. Your access is
> granted to `ldap@gcp.altostrat.com` (e.g. `zken@gcp.altostrat.com`). Signing in
> as `@google.com` will fail every command below with `PERMISSION_DENIED`, even
> though you are "on the lab team" — the account simply isn't in the policy.

Your job during delivery is small: **grant each participant's Cloud Build service
account read access to the image, and point them at the guide.** The CodeMender
image is already built and published in the repo — you don't build it. (If a
rebuild is ever needed, the lab owner handles that.)

> **EAP note.** This CodeMender build is Early Access. The image bakes in an EAP
> server credential (hence "sensitive" below), and the participant scripts work
> around a few current gaps (e.g. `cm fix --export` is unimplemented). See the
> guide's *Production hardening & EAP caveats* section and `README.md` for the
> full list — worth mentioning to participants up front.

**See also:** repo overview and architecture in [`README.md`](README.md);
participant guide at **https://cm-ci-lab.cedemo.app**.

---

## Before you start

You're ready to deliver once all of these are true:

- **Your `ldap@gcp.altostrat.com` identity is granted.** It holds
  `roles/artifactregistry.admin` on the `codemender` repo plus `roles/viewer` and
  `roles/serviceusage.serviceUsageConsumer` on the central project — that's what
  lets you grant participants access. Grants are managed by the lab owner; if the
  image check below fails, you're likely not granted yet.
- **`gcloud` is authenticated as your `@gcp.altostrat.com` account** and pointed
  at the central project. Log in explicitly — if you've used `gcloud` with a
  `@google.com` account before, it may still be the active one:
  ```bash
  gcloud auth login zken@gcp.altostrat.com   # ◀ your own ldap@gcp.altostrat.com
  export CENTRAL_PROJECT=zken-genai   # the project that hosts the codemender repo
  export REGION=us-central1
  gcloud config set project "$CENTRAL_PROJECT"

  gcloud config get-value account     # must print ldap@gcp.altostrat.com
  ```
- **You can see the image** — confirms your access:
  ```bash
  gcloud artifacts docker images list \
    "$REGION-docker.pkg.dev/$CENTRAL_PROJECT/codemender"
  ```
  `PERMISSION_DENIED` here means one of two things: you're signed in as the wrong
  account (re-check `gcloud config get-value account`), or your
  `@gcp.altostrat.com` identity hasn't been granted yet — ask the lab owner.

---

## What you provide to participants

1. The **image URL** (goes in their `_CM_IMAGE`) — generate the exact,
   digest-pinned reference as shown in *Get the exact image URL to share* below.
2. **Read access on the image** for each participant's Cloud Build service
   account(s) — collect their project number, grant both SA variants (below).
3. The lab URL: **https://cm-ci-lab.cedemo.app**

Everything else — state bucket, tokens, scripts, pipeline — is the participant's
own work in the guide.

> **What the image is:** a deliberately minimal toolbox — the `cm` binary plus
> node/npm (so `cm find verify` can build & run Juice Shop to reproduce an
> exploit), git, jq, and gcsfuse for GCS-backed state. It bakes in **no**
> orchestration; participants write the find/verify/fix scripts themselves.

---

## Get the exact image URL to share

Generate the URL right before you announce it rather than hand-typing it. Hand out
the **digest-pinned** form so every participant builds against the identical image
even if a tag is later re-pushed:

```bash
gcloud artifacts docker images describe \
  "$REGION-docker.pkg.dev/$CENTRAL_PROJECT/codemender/codemender-ci:v0.2.0" \
  --format='value(image_summary.fully_qualified_digest)'
# -> us-central1-docker.pkg.dev/zken-genai/codemender/codemender-ci@sha256:a1c470…
```

To see which tags exist first (e.g. after a rotation), list them with digests:

```bash
gcloud artifacts docker images list \
  "$REGION-docker.pkg.dev/$CENTRAL_PROJECT/codemender" --include-tags \
  --format='table(tags, version)'
```

Paste the digest-pinned URL into the sheet / your announcement as `_CM_IMAGE`. A
plain tag like `:v0.2.0` also works, but a tag can be re-pushed to a different
image — the digest can't.

---

## Grant participants image access

The image is pulled **inside Cloud Build**, so it is pulled by each participant's
**Cloud Build service account**, never by the person (they can't `docker pull` on
their laptops). Grant reader to that SA. Because the image embeds a **sensitive
EAP credential** (see Security), keep this a **tight, per-participant grant**
scoped to exactly the SAs that need it.

You need each participant's **project number** — the two build-SA emails are
fully derivable from it (`PROJNUM@cloudbuild…` and `PROJNUM-compute@developer…`),
so you collect one short number, not two long emails.

### 1 — Share a Google Sheet for participants to submit to

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

### 2 — Extract the submissions and grant both build SAs

**One participant (ad-hoc).** If you were just handed a single project number,
grant its two build SAs directly:

```bash
PROJNUM=739082641234   # ◀ the participant's project NUMBER
for SA in "${PROJNUM}@cloudbuild.gserviceaccount.com" \
          "${PROJNUM}-compute@developer.gserviceaccount.com"; do
  gcloud artifacts repositories add-iam-policy-binding codemender \
    --location="$REGION" --project="$CENTRAL_PROJECT" \
    --member="serviceAccount:${SA}" --role="roles/artifactregistry.reader"
done
```

**A cohort.** Pull the project-number column out of the sheet into
`project-numbers.txt`, one number per line (File → Download → **CSV**, then keep
that column — or just copy it). Then run the same grant over every row.
`add-iam-policy-binding` is **idempotent** (re-adding a member is a no-op), so you
can run it repeatedly — even on a `watch` during the lab — as new rows arrive,
without tracking who's already done:

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
  On a **brand-new project the legacy SA isn't created at all** — the build runs
  as `-compute@developer`. Granting the legacy SA anyway is harmless (IAM accepts
  a binding for an SA that doesn't exist), so keep both in the loop rather than
  guessing which one a given project uses.
- **Repo-scoped, so rotation-proof.** These bindings are on the `codemender`
  repo, not on a tag — they cover every current and future image version, so you
  never re-grant when the image is rotated.
- **Revoke after the cohort.** Because the baked key is extractable from the
  image and cannot be rotated (see Security), the real post-lab mitigation is to
  **remove these grants** — swap `add-iam-policy-binding` for
  `remove-iam-policy-binding` in the loop.
- *Optional automation:* an Apps Script / Cloud Function on form-submit could
  apply the grant itself, but that needs a standing SA with
  `artifactregistry.admin` on the repo — more attack surface than a one-off lab
  warrants. Prefer the manual idempotent loop.

**Fallback — `allAuthenticatedUsers` (avoid unless you must).** A single broad
grant covers every build SA with nothing to collect — but the baked key is a
**Google API key extractable from the image with `strings`**, and it **can't be
rotated** (only the CM team can). So this grant effectively publishes a live,
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

## Onboarding a new facilitator (lab owner only)

Facilitators are bound **individually**, by `ldap@gcp.altostrat.com` identity.
A group (`cm-ci-lab-admin`) is still bound on the repo for historical reasons,
but **don't add new facilitators to it** — Argolis blocks adding `@google.com`
members, and the group itself lives in a different domain, so direct bindings are
the supported path.

```bash
P=zken-genai
M="user:newperson@gcp.altostrat.com"   # ◀ ldap@gcp.altostrat.com — never @google.com

# grant-participants power, scoped to the repo
gcloud artifacts repositories add-iam-policy-binding codemender \
  --location=us-central1 --project="$P" --member="$M" --role="roles/artifactregistry.admin"
# operate in the central project
gcloud projects add-iam-policy-binding "$P" --member="$M" --role="roles/viewer" --condition=None
gcloud projects add-iam-policy-binding "$P" --member="$M" \
  --role="roles/serviceusage.serviceUsageConsumer" --condition=None
```

All three are idempotent — safe to re-run. To offboard, swap
`add-iam-policy-binding` for `remove-iam-policy-binding`.

> **The identity must already exist.** `gcloud` fails with **Error 2028** ("Email
> addresses and domains must be associated with an active Google Account") if the
> person has no `@gcp.altostrat.com` account yet. That's a provisioning
> prerequisite, not something you can work around with a different binding.

## Rotating the image

Publishing a new image version (new tag/digest) is the **lab owner's** job. When
it happens, your only action is to re-share the URL:

- **Re-share.** Re-run *Get the exact image URL to share* and post the new
  digest-pinned reference; participants update `_CM_IMAGE`.
- **No re-grant.** The reader bindings are repo-scoped, so they already cover the
  new version.
- **⚠ Moving the repo is the exception — it invalidates every grant.** The
  bindings live *on the repo*. Publishing to a **different repo or project**
  leaves them all behind, and the new repo starts with an empty IAM policy — so
  **every participant must be re-granted** (re-run the cohort loop below against
  the new `CENTRAL_PROJECT`). Participants see the same failure as no grant at
  all: the pipeline's image pull fails with `denied` at step 0. Same rule as
  Secret Manager: IAM lives on the resource, not the name.
- **Not a security control.** The baked key is identical across every tag and
  extractable from any of them, and you can't re-key it — so rotating the URL only
  versions the toolbox, it does **not** re-secure the credential. The real
  mitigation stays: scope access to the collected SAs and **revoke after the
  cohort** (see Security).

---

## Security

- **The image is sensitive — and irreducibly so.** The CodeMender API key is a
  Google API key baked into the `cm` binary at build time (a
  `-X …config.bakedAPIKey` ldflag). It is **extractable from the image in one
  command** (`strings /usr/local/bin/cm | grep AIza`) and sent as the
  `x-goog-api-key` header, so anyone who can pull the image can call the CM
  backend *directly*, image or not. There is **no runtime override** (config
  exposes only `server.endpoint`, no `api_key` field), and the key **cannot be
  rotated** without Google's internal build tooling. So **access control is the
  only protection**: keep image access scoped to the collected build SAs and
  **revoke after the cohort**. To make the image non-sensitive, ask the CM team
  for a build that reads the key at **runtime** (env / Secret Manager) or issues
  short-lived keys.
- **Repo admin = destroy power.** Facilitators hold `artifactregistry.admin` on
  the repo, i.e. the ability to overwrite or delete the only copy of the image.
  Keep this to trusted facilitators. It's broader than the job strictly needs
  (facilitators only *grant readers*), but there's no predefined "grant-only"
  role — it is at least scoped to the repo, not the project.
- **Facilitator identities are `ldap@gcp.altostrat.com`, bound directly.** The
  central project is Argolis, and Domain Restricted Sharing bars `@google.com`
  principals from its IAM policy entirely. Bindings are made per-identity on the
  repo and the project (see below) rather than via a group.
- **The web guide is public** (GCS static site behind an HTTPS LB) but contains
  only placeholders — no project IDs, tokens, service-account emails, or keys.
