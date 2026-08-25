#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator="$ROOT/os/tests/validate-boot-test-report.sh"
fixture="$ROOT/os/tests/boot-test-report.example.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

BEDROCK_ALLOW_FIXTURE_BOOT_REPORT=1 sh "$validator" "$fixture" >/dev/null
if sh "$validator" "$fixture" >/dev/null 2>&1; then
  printf 'error: fixture boot report passed as physical evidence\n' >&2
  exit 1
fi

reject() {
  label=$1 filter=$2
  jq "$filter" "$fixture" > "$work/$label.json"
  if BEDROCK_ALLOW_FIXTURE_BOOT_REPORT=1 sh "$validator" "$work/$label.json" >/dev/null 2>&1; then
    printf 'error: boot-report validator accepted %s evidence\n' "$label" >&2
    exit 1
  fi
}
reject qemu-platform '.platform = "qemu"'
reject wrong-generation '.platform = "hyper-v" | .platform_generation = null'
reject missing-inventory '.inventory.network = false'
reject unverified-image '.same_image_verified = false'
reject private-field '.mac_address = "private"'
reject unknown-field '.unexpected = true'

jq '.mode = "physical"' "$fixture" > "$work/vmware.json"
sh "$validator" "$work/vmware.json" >/dev/null
jq '.mode = "physical" | .platform = "hyper-v" | .platform_generation = "generation-2"' \
  "$fixture" > "$work/hyper-v.json"
sh "$validator" "$work/hyper-v.json" >/dev/null

printf 'Bedrock boot-test acceptance-report tests passed.\n'
