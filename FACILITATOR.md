# CodeMender CI Lab — Facilitator Guide

> **Not for participants.** This is for facilitators **delivering** the lab. It
> assumes you are a member of the **`cm-ci-lab-admin`** group and therefore have
> access to the central GCP project and the `codemender` Artifact Registry repo.
> Participants use the web guide at **https://cm-ci-lab.cedemo.app** and never
> see this file.

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

- **You're in the `cm-ci-lab-admin` group.** Membership carries
  `roles/artifactregistry.admin` on the `codemender` repo plus access to the
  central project — that's what lets you grant participants access. Membership is
  managed by the lab owner; if the image check below fails, you're likely not in
  the group yet.
- **`gcloud` is authenticated** as your facilitator account and pointed at the
  central project:
  ```bash
  gcloud auth login
  gcloud config set project <CENTRAL_PROJECT>
  export REGION=us-central1
  ```
- **You can see the image** — this both confirms your access and gives you the
  exact URL to share:
  ```bash
  gcloud artifacts docker images list \
    "$REGION-docker.pkg.dev/<CENTRAL_PROJECT>/codemender" --include-tags
  ```

---

## What you provide to participants

1. The **image URL** — the tagged path from the listing above, e.g.
   `<REGION>-docker.pkg.dev/<CENTRAL_PROJECT>/codemender/codemender-ci:<TAG>`
   (goes in their `_CM_IMAGE`). A digest-pinned reference works too and is more
   reproducible.
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
      --location="$REGION" --project="<CENTRAL_PROJECT>" \
      --member="serviceAccount:${SA}" --role="roles/artifactregistry.reader"
  done
done < project-numbers.txt
```

- Grant **both** SAs. A project builds as the legacy `@cloudbuild` SA *or* the
  default `-compute@developer` SA; if you grant only one and the build uses the
  other, the image pull fails with `denied` (the log shows which SA it used).
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
- **Repo admin = destroy power.** Membership of `cm-ci-lab-admin` grants
  `artifactregistry.admin`, i.e. the ability to overwrite or delete the only copy
  of the image. Keep membership to trusted facilitators.
- **The web guide is public** (GCS static site behind an HTTPS LB) but contains
  only placeholders — no project IDs, tokens, service-account emails, or keys.
