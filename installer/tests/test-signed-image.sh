#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/keys" "$work/source" "$work/release"
printf 'deterministic Bedrock installer image\n' > "$work/source/bedrock-os-amd64.iso"

BEDROCK_ALLOW_EPHEMERAL_KEYS=1 "$ROOT/os/scripts/generate-development-keys.sh" "$work/keys" >/dev/null
key="$work/keys/DO-NOT-SHIP-development.key"
cert="$work/keys/DO-NOT-SHIP-development.crt"
BEDROCK_RELEASE_KEY="$key" BEDROCK_RELEASE_CERT="$cert" \
  sh "$ROOT/installer/core/create-signed-image-release.sh" 0.3.0-test iso \
  "$work/source/bedrock-os-amd64.iso" "$work/release" >/dev/null
sh "$ROOT/installer/core/verify-signed-image.sh" "$work/release" "$cert" bedrock-os-amd64.iso >/dev/null

cp "$work/release/bedrock-os-amd64.iso" "$work/good.iso"
printf x >> "$work/release/bedrock-os-amd64.iso"
if sh "$ROOT/installer/core/verify-signed-image.sh" "$work/release" "$cert" bedrock-os-amd64.iso >/dev/null 2>&1; then
  printf 'error: altered installer image was accepted\n' >&2
  exit 1
fi
mv "$work/good.iso" "$work/release/bedrock-os-amd64.iso"

if sh "$ROOT/installer/core/verify-signed-image.sh" "$work/release" "$cert" bedrock-os-amd64.raw.zst >/dev/null 2>&1; then
  printf 'error: unexpected installer image name was accepted\n' >&2
  exit 1
fi
printf x >> "$work/release/manifest.json"
if sh "$ROOT/installer/core/verify-signed-image.sh" "$work/release" "$cert" bedrock-os-amd64.iso >/dev/null 2>&1; then
  printf 'error: altered release manifest was accepted\n' >&2
  exit 1
fi

printf 'Bedrock signed installer image accepted valid content and rejected tampering.\n'
