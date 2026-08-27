#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner="$ROOT/installer/acceptance/run-linux-real-device.sh"
validator="$ROOT/installer/acceptance/validate-real-device-report.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

if sh "$runner" missing missing missing missing missing "$work/report.json" >/dev/null 2>&1; then
  printf 'error: acceptance runner did not require destructive opt-in\n' >&2
  exit 1
fi

mkdir -p "$work/keys" "$work/source" "$work/release" "$work/targets"
printf 'Bedrock acceptance fixture image\n' > "$work/source/bedrock-os-amd64.iso"
truncate -s 8589934592 "$work/targets/usb.img"
BEDROCK_ALLOW_EPHEMERAL_KEYS=1 \
  sh "$ROOT/os/scripts/generate-development-keys.sh" "$work/keys" >/dev/null
cert="$work/keys/DO-NOT-SHIP-development.crt"
BEDROCK_RELEASE_KEY="$work/keys/DO-NOT-SHIP-development.key" \
BEDROCK_RELEASE_CERT="$cert" \
  sh "$ROOT/installer/core/create-signed-image-release.sh" 0.3.0-acceptance-fixture iso \
    "$work/source/bedrock-os-amd64.iso" "$work/release" >/dev/null
target_path="$work/targets/usb.img"
jq -n --arg path "$target_path" '{
  schema:1,generated_at:"2026-08-24T00:00:00Z",
  targets:[{id:"fixture-usb",path:$path,model:"Bedrock Fixture USB",
    size_bytes:8589934592,removable:true,system:false,mounted:false,read_only:false}]
}' > "$work/inventory.json"
confirmation="ERASE Bedrock Fixture USB — $target_path — 8589934592"
BEDROCK_REAL_DEVICE_ACCEPTANCE='I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE' \
BEDROCK_ACCEPTANCE_TARGET_PATH="$target_path" \
BEDROCK_ACCEPTANCE_TARGET_SIZE=8589934592 \
BEDROCK_ACCEPTANCE_FIXTURE_MODE=1 \
BEDROCK_ACCEPTANCE_FIXTURE_INVENTORY="$work/inventory.json" \
BEDROCK_ACCEPTANCE_FIXTURE_TARGET_DIR="$work/targets" \
  sh "$runner" "$work/release" "$cert" bedrock-os-amd64.iso fixture-usb \
    "$confirmation" "$work/fixture-report.json" >/dev/null

if sh "$validator" "$work/fixture-report.json" >/dev/null 2>&1; then
  printf 'error: fixture evidence was accepted as physical-device evidence\n' >&2
  exit 1
fi
BEDROCK_ALLOW_FIXTURE_ACCEPTANCE_REPORT=1 \
  sh "$validator" "$work/fixture-report.json" >/dev/null

jq '.platform = "macos" | .target.path = "/dev/disk8"' \
  "$work/fixture-report.json" > "$work/macos-fixture-report.json"
BEDROCK_ALLOW_FIXTURE_ACCEPTANCE_REPORT=1 \
  sh "$validator" "$work/macos-fixture-report.json" >/dev/null
jq '.platform = "windows" | .target.path = "\\\\.\\PhysicalDrive2"' \
  "$work/fixture-report.json" > "$work/windows-fixture-report.json"
BEDROCK_ALLOW_FIXTURE_ACCEPTANCE_REPORT=1 \
  sh "$validator" "$work/windows-fixture-report.json" >/dev/null

jq '.mode = "physical" | .target.path = "/dev/sdz" |
    .boot_completed_at = "2026-08-25T01:00:00Z" |
    .checks.booted_from_media = true | .checks.guided_installer_opened = true' \
  "$work/fixture-report.json" > "$work/linux-physical-shape.json"
sh "$validator" "$work/linux-physical-shape.json" >/dev/null
jq '.mode = "physical" | .boot_completed_at = "2026-08-25T01:00:00Z" |
    .checks.booted_from_media = true | .checks.guided_installer_opened = true' \
  "$work/macos-fixture-report.json" > "$work/macos-physical-shape.json"
sh "$validator" "$work/macos-physical-shape.json" >/dev/null
jq '.mode = "physical" | .boot_completed_at = "2026-08-25T01:00:00Z" |
    .checks.booted_from_media = true | .checks.guided_installer_opened = true' \
  "$work/windows-fixture-report.json" > "$work/windows-physical-shape.json"
sh "$validator" "$work/windows-physical-shape.json" >/dev/null

jq '.mode = "physical" | .target.path = "/dev/sdz"' \
  "$work/fixture-report.json" > "$work/unbooted-physical.json"
if sh "$validator" "$work/unbooted-physical.json" >/dev/null 2>&1; then
  printf 'error: unbooted removable media was accepted as physical evidence\n' >&2
  exit 1
fi

jq '.checks.reread_checksum = false' "$work/fixture-report.json" > "$work/failed-report.json"
if BEDROCK_ALLOW_FIXTURE_ACCEPTANCE_REPORT=1 \
  sh "$validator" "$work/failed-report.json" >/dev/null 2>&1; then
  printf 'error: incomplete acceptance evidence was accepted\n' >&2
  exit 1
fi

grep -q 'I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE' "$runner"
grep -q 'I CONFIRM THIS LARGE DRIVE IS DISPOSABLE' "$runner"
grep -q '\[ ! -e "$sysfs/partition" \]' "$runner"
grep -q 'cat "$sysfs/removable"' "$runner"
printf 'Real-device acceptance gates and evidence validator are valid.\n'
