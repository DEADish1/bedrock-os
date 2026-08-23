#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
adapter="$ROOT/installer/adapters/macos-list-targets.sh"
fixture="$ROOT/installer/tests/macos-disks.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

BEDROCK_MACOS_DISKS_JSON=$(cat "$fixture") sh "$adapter" > "$work/inventory.json"
jq -e '
  .schema == 1 and (.targets | length == 3) and
  ([.targets[] | select(.path == "/dev/disk0" and .system == true and .removable == false)] | length == 1) and
  ([.targets[] | select(.path == "/dev/disk8" and .system == false and .removable == true and .mounted == false)] | length == 1) and
  ([.targets[] | select(.path == "/dev/disk9" and .mounted == true)] | length == 1) and
  ([.targets[].id] | unique | length == 3)
' "$work/inventory.json" >/dev/null

safe_id=$(jq -r '.targets[] | select(.path == "/dev/disk8") | .id' "$work/inventory.json")
sh "$ROOT/installer/core/validate-target-selection.sh" "$work/inventory.json" "$safe_id" \
  'ERASE Bedrock Test USB — /dev/disk8 — 17179869184' >/dev/null

BEDROCK_MACOS_DISKS_JSON=$(jq '.root_parent = ""' "$fixture") sh "$adapter" > "$work/unknown-root.json"
jq -e '[.targets[] | select(.system != true)] | length == 0' "$work/unknown-root.json" >/dev/null

printf 'Bedrock macOS target enumeration tests passed.\n'
