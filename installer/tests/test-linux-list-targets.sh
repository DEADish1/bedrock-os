#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
adapter="$ROOT/installer/adapters/linux-list-targets.sh"
fixture="$ROOT/installer/tests/linux-lsblk.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

BEDROCK_LSBLK_JSON=$(cat "$fixture") BEDROCK_ROOT_PARENT=nvme0n1 sh "$adapter" > "$work/inventory.json"

jq -e '
  .schema == 1 and (.generated_at | type == "string") and
  (.targets | length == 3) and
  ([.targets[] | select(.path == "/dev/nvme0n1" and .system == true and .removable == false)] | length == 1) and
  ([.targets[] | select(.path == "/dev/sdb" and .model == "Bedrock USB" and .removable == true and .mounted == false)] | length == 1) and
  ([.targets[] | select(.path == "/dev/sdc" and .mounted == true)] | length == 1) and
  ([.targets[].id] | unique | length == 3)
' "$work/inventory.json" >/dev/null

safe_id=$(jq -r '.targets[] | select(.path == "/dev/sdb") | .id' "$work/inventory.json")
sh "$ROOT/installer/core/validate-target-selection.sh" "$work/inventory.json" "$safe_id" \
  'ERASE Bedrock USB — /dev/sdb — 17179869184' >/dev/null

BEDROCK_LSBLK_JSON=$(jq 'walk(if type == "object" and has("mountpoints") then .mountpoints = [null] else . end)' "$fixture") \
  sh "$adapter" > "$work/unknown-root.json"
jq -e '[.targets[] | select(.system != true)] | length == 0' "$work/unknown-root.json" >/dev/null

printf 'Bedrock Linux target enumeration tests passed.\n'
