#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
mkdir -p "$work/a" "$work/b"
for directory in "$work/a" "$work/b"; do
  printf 'deterministic image\n' > "$directory/bedrock-os-amd64.iso"
  (cd "$directory" && sha256sum bedrock-os-amd64.iso > bedrock-os-amd64.iso.sha256)
  printf 'base-files=13.8+deb13u2\nlinux-image-amd64=6.12.57-1\n' > "$directory/packages.lock"
  printf '{"schema":1,"product":"Bedrock Server OS","version":"0.2.0-dev","architecture":"amd64","source_date_epoch":1,"commit":"test","live_build":"test"}\n' > "$directory/bedrock-build-manifest.json"
done
"$ROOT/os/scripts/compare-reproducible-builds.sh" "$work/a" "$work/b" >/dev/null
printf x >> "$work/b/bedrock-os-amd64.iso"
if "$ROOT/os/scripts/compare-reproducible-builds.sh" "$work/a" "$work/b" >/dev/null 2>&1; then
  printf 'error: mismatched image was accepted as reproducible\n' >&2
  exit 1
fi
printf 'Bedrock reproducibility comparison accepts matches and rejects drift.\n'
