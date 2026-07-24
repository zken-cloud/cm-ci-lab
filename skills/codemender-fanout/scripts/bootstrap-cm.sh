#!/usr/bin/env bash
# Download the public-preview CodeMender CLI for this OS/arch into $1 (default ~/.local/bin).
set -euo pipefail

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)   name=cm-darwin-arm64.zip ;;
  Darwin-x86_64)  name=cm-darwin-amd64.zip ;;
  Linux-x86_64)   name=cm-linux-amd64.zip ;;
  Linux-aarch64)  name=cm-linux-arm64.zip ;;
  *) echo "❌ unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

dest="${1:-$HOME/.local/bin}"; mkdir -p "$dest"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

echo "⬇️  downloading $name …"
gcloud artifacts generic download --project=cmoc-prod --location=us \
  --repository=codemender-cli-production --package=cm --version=stable \
  --name="$name" --destination="$tmp"
( cd "$tmp" && unzip -oq "$name" && chmod +x cm && mv cm "$dest/cm" )

echo "✅ installed cm → $dest/cm"
case ":$PATH:" in *":$dest:"*) : ;; *) echo "⚠️  add $dest to your PATH" ;; esac
"$dest/cm" --version || true
