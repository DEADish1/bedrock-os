#!/bin/sh
set -eu

OUT_DIR=${1:-}
[ -n "$OUT_DIR" ] || { printf 'usage: %s OUT_DIR\n' "$0" >&2; exit 2; }
[ -d "$OUT_DIR" ] || { printf 'error: output directory does not exist\n' >&2; exit 1; }

manifest="$OUT_DIR/bedrock-build-manifest.json"
checksum=$(find "$OUT_DIR" -maxdepth 1 -name '*.iso.sha256' -type f -print -quit)
iso=$(find "$OUT_DIR" -maxdepth 1 -name '*.iso' -type f -print -quit)
sbom="$OUT_DIR/bedrock-os.spdx.json"

[ -s "$manifest" ] || { printf 'error: build manifest missing\n' >&2; exit 1; }
[ -n "$checksum" ] && [ -s "$checksum" ] || { printf 'error: checksum missing\n' >&2; exit 1; }
[ -n "$iso" ] && [ -s "$iso" ] || { printf 'error: ISO missing\n' >&2; exit 1; }
[ -s "$sbom" ] && [ ! -L "$sbom" ] || { printf 'error: SPDX SBOM missing or indirect\n' >&2; exit 1; }

command -v jq >/dev/null 2>&1 && jq -e '
  .schema == 1 and .product == "Bedrock Server OS" and .architecture == "amd64" and
  (.protected_system_writer_enabled | type == "boolean")
' "$manifest" >/dev/null
jq -e '
  .spdxVersion == "SPDX-2.3" and .dataLicense == "CC0-1.0" and
  .SPDXID == "SPDXRef-DOCUMENT" and
  .documentDescribes == ["SPDXRef-Bedrock-Server-OS"] and
  (.packages | type == "array" and length > 0) and
  ([.packages[].SPDXID] | unique | length) == (.packages | length)
' "$sbom" >/dev/null
(cd "$OUT_DIR" && sha256sum -c "$(basename "$checksum")")

if [ -e "$OUT_DIR/bedrock-os-amd64.raw" ]; then
  [ -s "$OUT_DIR/bedrock-os-amd64.raw.sha256" ] || { printf 'error: raw image checksum missing\n' >&2; exit 1; }
  [ -s "$OUT_DIR/bedrock-signing-manifest.json" ] || { printf 'error: signing manifest missing\n' >&2; exit 1; }
  jq -e '.schema == 1 and (.signing_mode == "development-ephemeral" or .signing_mode == "release-protected") and (.release_eligible == (.signing_mode == "release-protected"))' "$OUT_DIR/bedrock-signing-manifest.json" >/dev/null
  (cd "$OUT_DIR" && sha256sum -c bedrock-os-amd64.raw.sha256)
fi
printf 'Bedrock image artifacts verified.\n'
