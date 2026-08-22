#!/bin/sh
set -eu

OUT_DIR=${1:-}
[ -n "$OUT_DIR" ] || { printf 'usage: %s OUT_DIR\n' "$0" >&2; exit 2; }
[ -d "$OUT_DIR" ] || { printf 'error: output directory does not exist\n' >&2; exit 1; }

manifest="$OUT_DIR/bedrock-build-manifest.json"
checksum=$(find "$OUT_DIR" -maxdepth 1 -name '*.iso.sha256' -type f -print -quit)
iso=$(find "$OUT_DIR" -maxdepth 1 -name '*.iso' -type f -print -quit)

[ -s "$manifest" ] || { printf 'error: build manifest missing\n' >&2; exit 1; }
[ -n "$checksum" ] && [ -s "$checksum" ] || { printf 'error: checksum missing\n' >&2; exit 1; }
[ -n "$iso" ] && [ -s "$iso" ] || { printf 'error: ISO missing\n' >&2; exit 1; }

command -v jq >/dev/null 2>&1 && jq -e '.schema == 1 and .product == "Bedrock Server OS" and .architecture == "amd64"' "$manifest" >/dev/null
(cd "$OUT_DIR" && sha256sum -c "$(basename "$checksum")")

if [ -e "$OUT_DIR/bedrock-os-amd64.raw" ]; then
  [ -s "$OUT_DIR/bedrock-os-amd64.raw.sha256" ] || { printf 'error: raw image checksum missing\n' >&2; exit 1; }
  [ -s "$OUT_DIR/bedrock-signing-manifest.json" ] || { printf 'error: signing manifest missing\n' >&2; exit 1; }
  jq -e '.schema == 1 and (.signing_mode == "development-ephemeral" or .signing_mode == "release-protected") and (.release_eligible == (.signing_mode == "release-protected"))' "$OUT_DIR/bedrock-signing-manifest.json" >/dev/null
  (cd "$OUT_DIR" && sha256sum -c bedrock-os-amd64.raw.sha256)
fi
printf 'Bedrock image artifacts verified.\n'
