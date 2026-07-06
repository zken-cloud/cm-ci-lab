# CodeMender CI toolbox image.
#
# A deliberately MINIMAL image: the CodeMender client plus the build/runtime
# tools needed to (a) scan and remediate a Node.js project and (b) let
# `cm find verify` actually build & run OWASP Juice Shop to reproduce an
# exploit. It carries NO orchestration logic — participants author the find /
# verify / fix scripts and the Cloud Build pipeline themselves during the lab.
#
# Base: Debian-based Node.js (glibc). Required because:
#   • `cm` is dynamically linked against glibc, and
#   • Juice Shop builds and runs on Node 22 (npm, node-gyp, etc.).
FROM node:22-bookworm-slim

# Build & runtime dependencies:
#   git, ca-certificates      clone/commit/push; TLS to the CM server & GitHub
#   curl, jq                  GitHub REST API; parse `cm report` JSON output
#   build-essential, python3  node-gyp / native npm modules used by Juice Shop
#   fuse3, gcsfuse            mount a GCS bucket for CodeMender state (see lab)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates curl jq gnupg build-essential python3 fuse3 \
 && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt gcsfuse-bookworm main" \
      > /etc/apt/sources.list.d/gcsfuse.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gcsfuse \
 && rm -rf /var/lib/apt/lists/*

# The CodeMender client. Build context must contain the `cm-linux` binary.
COPY cm-linux /usr/local/bin/cm
RUN chmod 0755 /usr/local/bin/cm

# Sanity checks: the toolbox has everything the lab relies on.
RUN cm --version && node --version && npm --version \
 && git --version && jq --version && gcsfuse --version

WORKDIR /workspace
