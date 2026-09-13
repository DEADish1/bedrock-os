#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

printf '%s\n' 'base-files=13.8+deb13u2' 'linux-image-amd64=6.12.57-1' > "$work/packages.lock"
run() {
  "$ROOT/os/scripts/create-spdx-sbom.sh" "$work/packages.lock" "$1" 0.2.0-dev Debian-13 amd64 0123456789abcdef 1789310000
}
run "$work/a.spdx.json"
run "$work/b.spdx.json"
cmp -s "$work/a.spdx.json" "$work/b.spdx.json"
jq -e '
  .spdxVersion=="SPDX-2.3" and .dataLicense=="CC0-1.0" and
  .creationInfo.created=="2026-09-13T14:33:20Z" and
  .documentDescribes==["SPDXRef-Bedrock-Server-OS"] and
  (.packages|length)==3 and
  (.packages[1].externalRefs[0].referenceLocator|startswith("pkg:deb/debian/base-files@")) and
  (.relationships|length)==2 and
  ([.packages[].SPDXID]|unique|length)==3
' "$work/a.spdx.json" >/dev/null

if "$ROOT/os/scripts/create-spdx-sbom.sh" "$work/missing" "$work/bad.json" 1 Debian amd64 commit 1 >/dev/null 2>&1; then
  printf 'error: missing package input was accepted\n' >&2
  exit 1
fi
printf 'Deterministic SPDX SBOM tests passed.\n'
