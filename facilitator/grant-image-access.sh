#!/usr/bin/env bash
#
# grant-image-access.sh — give participants' Cloud Build service accounts read
# access to the CodeMender lab image.
#
# Usage:
#   ./grant-image-access.sh                 # prompts for project numbers/IDs
#   ./grant-image-access.sh 123,456 789     # or pass them as arguments
#
# Accepts project NUMBERS or project IDs, comma- and/or space-separated; IDs are
# resolved to numbers automatically. Re-running is safe — IAM bindings are
# idempotent, and the script reports what was already in place.
#
# Auth: uses your active gcloud account (see the note in preflight below).
set -euo pipefail

CENTRAL_PROJECT="${CENTRAL_PROJECT:-zken-genai}"
REPO="${REPO:-codemender}"
REGION="${REGION:-us-central1}"
ROLE="roles/artifactregistry.reader"

bold=$'\e[1m'; red=$'\e[31m'; grn=$'\e[32m'; ylw=$'\e[33m'; dim=$'\e[2m'; off=$'\e[0m'
say()  { printf '%s\n' "$*"; }
die()  { printf '%s\n' "${red}✗ $*${off}" >&2; exit 1; }

usage() {
  cat <<USAGE
Grant participants' Cloud Build service accounts read access to the lab image.

  $(basename "$0")                          prompt for project numbers/IDs
  $(basename "$0") 123456789012             one
  $(basename "$0") 123,456 789              comma- and/or space-separated

Accepts project numbers or project IDs (IDs are resolved automatically).
Safe to re-run. Exits non-zero if any grant failed.

Env overrides: CENTRAL_PROJECT (${CENTRAL_PROJECT}), REPO (${REPO}), REGION (${REGION})
USAGE
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# ── Preflight ────────────────────────────────────────────────────────────────
command -v gcloud >/dev/null || die "gcloud not found on PATH."

ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
[[ -z "$ACCOUNT" || "$ACCOUNT" == "(unset)" ]] && die \
  "No active gcloud account. Run: gcloud auth login YOUR_LDAP@gcp.altostrat.com"

say "${bold}CodeMender lab — grant image access${off}"
say "  repo    : ${REGION}-docker.pkg.dev/${CENTRAL_PROJECT}/${REPO}"
say "  role    : ${ROLE}"
say "  as      : ${ACCOUNT}"

# The IAM writes below go through gcloud, which uses the account above — NOT the
# separate `gcloud auth application-default login` credential. Both come from
# your own login, so there is no key file either way.
case "$ACCOUNT" in
  *@google.com)
    say "${ylw}⚠ ${ACCOUNT} is a @google.com identity.${off}"
    say "${ylw}  The central project is Argolis; Domain Restricted Sharing blocks these."
    say "  Run: gcloud auth login YOUR_LDAP@gcp.altostrat.com${off}" ;;
esac

# Proves the facilitator actually has access before we prompt for anything.
# One member per line, scoped to the role we grant, so membership can be matched
# exactly (a substring match could false-positive and silently skip a grant).
MEMBERS="$(gcloud artifacts repositories get-iam-policy "$REPO" \
             --location="$REGION" --project="$CENTRAL_PROJECT" \
             --flatten='bindings[].members[]' --filter="bindings.role=${ROLE}" \
             --format='value(bindings.members)' 2>/dev/null)" \
  || die "Can't read the repo IAM policy as ${ACCOUNT}.
  Either you're signed in as the wrong account, or your identity hasn't been
  granted yet — ask the lab owner. See FACILITATOR.md."

# ── Collect input ────────────────────────────────────────────────────────────
if (( $# )); then
  RAW="$*"
else
  say ""
  say "Enter participant GCP project ${bold}numbers${off} or ${bold}IDs${off} (comma or space separated):"
  read -r -p "> " RAW
fi

# Split on commas and whitespace; drop empties.
read -r -a TOKENS <<< "$(printf '%s' "$RAW" | tr ',' ' ' | tr -s '[:space:]' ' ')"
(( ${#TOKENS[@]} )) || die "Nothing to do — no project numbers or IDs given."

# ── Grant ────────────────────────────────────────────────────────────────────
granted=0; already=0; failed=0
say ""
for TOKEN in "${TOKENS[@]}"; do
  if [[ "$TOKEN" == -* ]]; then
    # Never hand a flag to `gcloud projects describe` — it would print its own
    # help into PROJNUM and cascade into nonsense.
    say "${red}✗ ${TOKEN}${off} — not a project number or ID (see --help)"
    failed=$(( failed + 1 )); continue
  elif [[ "$TOKEN" =~ ^[0-9]+$ ]]; then
    PROJNUM="$TOKEN"; LABEL="$TOKEN"
  else
    # A project ID was pasted instead of a number — resolve it rather than fail.
    PROJNUM="$(gcloud projects describe "$TOKEN" --format='value(projectNumber)' 2>/dev/null || true)"
    if [[ ! "$PROJNUM" =~ ^[0-9]+$ ]]; then
      say "${red}✗ ${TOKEN}${off} — not a number, and no project with that ID is visible to you"
      failed=$(( failed + 1 )); continue
    fi
    LABEL="${TOKEN} → ${PROJNUM}"
  fi

  say "${bold}${LABEL}${off}"
  for SA in "${PROJNUM}@cloudbuild.gserviceaccount.com" \
            "${PROJNUM}-compute@developer.gserviceaccount.com"; do
    MEMBER="serviceAccount:${SA}"
    if grep -Fxq "$MEMBER" <<< "$MEMBERS"; then
      say "  ${dim}• ${SA} — already had access${off}"; already=$(( already + 1 )); continue
    fi
    if ERR="$(gcloud artifacts repositories add-iam-policy-binding "$REPO" \
                --location="$REGION" --project="$CENTRAL_PROJECT" \
                --member="$MEMBER" --role="$ROLE" 2>&1 >/dev/null)"; then
      say "  ${grn}✓${off} ${SA}"; granted=$(( granted + 1 ))
    elif [[ "$ERR" == *"does not exist"* ]]; then
      # IAM refuses bindings for service accounts that don't exist. Usually the
      # project number is wrong, or the participant hasn't enabled Cloud Build.
      say "  ${red}✗${off} ${SA} — ${bold}no such service account${off}"
      say "    ${dim}Check the project number, and that the participant has run:"
      say "    gcloud services enable cloudbuild.googleapis.com${off}"
      failed=$(( failed + 1 ))
    else
      say "  ${red}✗${off} ${SA} — grant failed"
      say "    ${dim}${ERR%%$'\n'*}${off}"
      failed=$(( failed + 1 ))
    fi
  done
done

# ── Summary ──────────────────────────────────────────────────────────────────
say ""
say "${bold}Done.${off} ${grn}${granted} granted${off}, ${already} already had access, ${red}${failed} failed${off}."
say "${dim}Both build SAs are granted because a project uses one or the other."
say "They are Google-managed service agents, so they won't appear in the"
say "participant's 'gcloud iam service-accounts list' — that's expected.${off}"
exit $(( failed > 0 ))
