#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/keys" "$work/source" "$work/release" "$work/targets"
printf 'Bedrock hybrid ISO test image\n' > "$work/source/bedrock-os-amd64.iso"
truncate -s 8589934592 "$work/targets/usb.img"

BEDROCK_ALLOW_EPHEMERAL_KEYS=1 "$ROOT/os/scripts/generate-development-keys.sh" "$work/keys" >/dev/null
key="$work/keys/DO-NOT-SHIP-development.key"
cert="$work/keys/DO-NOT-SHIP-development.crt"
BEDROCK_RELEASE_KEY="$key" BEDROCK_RELEASE_CERT="$cert" \
  sh "$ROOT/installer/core/create-signed-image-release.sh" 0.3.0-test iso \
  "$work/source/bedrock-os-amd64.iso" "$work/release" >/dev/null

target_path="$work/targets/usb.img"
jq -n --arg path "$target_path" '{
  schema:1, generated_at:"2026-08-23T23:00:00Z",
  targets:[{id:"test-usb",path:$path,model:"Bedrock Test USB",size_bytes:8589934592,
    removable:true,system:false,mounted:false,read_only:false}]
}' > "$work/inventory.json"
confirmation="ERASE Bedrock Test USB — $target_path — 8589934592"

BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_TARGET_DIR="$work/targets" \
  sh "$ROOT/installer/core/write-verified-image.sh" "$work/release" "$cert" bedrock-os-amd64.iso \
  "$work/inventory.json" test-usb "$confirmation" >/dev/null
expected_hash=$(shasum -a 256 "$work/source/bedrock-os-amd64.iso" | awk '{print $1}')
image_size=$(stat -c %s "$work/source/bedrock-os-amd64.iso" 2>/dev/null || stat -f %z "$work/source/bedrock-os-amd64.iso")
actual_hash=$(head -c "$image_size" "$target_path" | shasum -a 256 | awk '{print $1}')
[ "$actual_hash" = "$expected_hash" ]

if BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_TARGET_DIR="$work/targets" \
  sh "$ROOT/installer/core/write-verified-image.sh" "$work/release" "$cert" bedrock-os-amd64.iso \
  "$work/inventory.json" test-usb 'ERASE the USB' >/dev/null 2>&1; then
  printf 'error: writer accepted an incorrect destructive confirmation\n' >&2
  exit 1
fi

jq '.targets[0].size_bytes = 1' "$work/inventory.json" > "$work/too-small.json"
if BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_TARGET_DIR="$work/targets" \
  sh "$ROOT/installer/core/write-verified-image.sh" "$work/release" "$cert" bedrock-os-amd64.iso \
  "$work/too-small.json" test-usb "ERASE Bedrock Test USB — $target_path — 1" >/dev/null 2>&1; then
  printf 'error: writer accepted an undersized target\n' >&2
  exit 1
fi

printf 'Bedrock guarded media writer passed write, reread, and rejection tests.\n'
