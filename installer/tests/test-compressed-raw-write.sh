#!/bin/sh
set -eu

command -v zstd >/dev/null 2>&1 || { printf 'Bedrock compressed raw writer test skipped: zstd unavailable.\n'; exit 0; }
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/keys" "$work/source" "$work/release" "$work/targets"
printf 'expanded Bedrock raw disk bytes\n' > "$work/source/bedrock-os-amd64.raw"
zstd -q "$work/source/bedrock-os-amd64.raw" -o "$work/source/bedrock-os-amd64.raw.zst"
truncate -s 8589934592 "$work/targets/usb.img"

BEDROCK_ALLOW_EPHEMERAL_KEYS=1 "$ROOT/os/scripts/generate-development-keys.sh" "$work/keys" >/dev/null
key="$work/keys/DO-NOT-SHIP-development.key"
cert="$work/keys/DO-NOT-SHIP-development.crt"
BEDROCK_RELEASE_KEY="$key" BEDROCK_RELEASE_CERT="$cert" \
  sh "$ROOT/installer/core/create-signed-image-release.sh" 0.3.0-test raw-zst \
  "$work/source/bedrock-os-amd64.raw.zst" "$work/release" >/dev/null

target_path="$work/targets/usb.img"
jq -n --arg path "$target_path" '{schema:1,generated_at:"2026-08-23T23:00:00Z",targets:[
  {id:"raw-usb",path:$path,model:"Raw Test USB",size_bytes:8589934592,removable:true,system:false,mounted:false,read_only:false}
]}' > "$work/inventory.json"
confirmation="ERASE Raw Test USB — $target_path — 8589934592"
BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_TARGET_DIR="$work/targets" \
  sh "$ROOT/installer/core/write-verified-image.sh" "$work/release" "$cert" bedrock-os-amd64.raw.zst \
  "$work/inventory.json" raw-usb "$confirmation" >/dev/null

size=$(stat -c %s "$work/source/bedrock-os-amd64.raw" 2>/dev/null || stat -f %z "$work/source/bedrock-os-amd64.raw")
expected=$(shasum -a 256 "$work/source/bedrock-os-amd64.raw" | awk '{print $1}')
actual=$(head -c "$size" "$target_path" | shasum -a 256 | awk '{print $1}')
[ "$actual" = "$expected" ]
printf 'Bedrock compressed raw image passed expansion, write, reread, and verification.\n'
