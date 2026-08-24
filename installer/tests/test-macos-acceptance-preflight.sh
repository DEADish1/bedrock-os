#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$ROOT/installer/tests/macos-disks.json"
preflight="$ROOT/installer/acceptance/prepare-macos-real-device.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
inventory=$(BEDROCK_MACOS_DISKS_JSON="$(cat "$fixture")" \
  sh "$ROOT/installer/adapters/macos-list-targets.sh")
id=$(printf '%s\n' "$inventory" | jq -r '.targets[] | select(.path == "/dev/disk8") | .id')
confirmation='ERASE Bedrock Test USB — /dev/disk8 — 17179869184'
BEDROCK_REAL_DEVICE_ACCEPTANCE='I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE' \
BEDROCK_ACCEPTANCE_TARGET_PATH=/dev/disk8 BEDROCK_ACCEPTANCE_TARGET_SIZE=17179869184 \
BEDROCK_ACCEPTANCE_FIXTURE_MODE=1 BEDROCK_MACOS_DISKS_JSON="$(cat "$fixture")" \
  sh "$preflight" "$id" "$confirmation" "$work/plan.json" >/dev/null
jq -e '.mode == "fixture" and .platform == "macos" and .ready_for_writer == false and
  .checks.fresh_inventory == true and .checks.whole_device == true' "$work/plan.json" >/dev/null

if BEDROCK_REAL_DEVICE_ACCEPTANCE='I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE' \
  BEDROCK_ACCEPTANCE_TARGET_PATH=/dev/disk8s1 BEDROCK_ACCEPTANCE_TARGET_SIZE=17179869184 \
  BEDROCK_ACCEPTANCE_FIXTURE_MODE=1 BEDROCK_MACOS_DISKS_JSON="$(cat "$fixture")" \
  sh "$preflight" "$id" "$confirmation" "$work/bad.json" >/dev/null 2>&1; then
  printf 'error: macOS preflight accepted a mismatched partition-shaped path\n' >&2
  exit 1
fi
printf 'macOS disposable-drive acceptance preflight is valid.\n'
