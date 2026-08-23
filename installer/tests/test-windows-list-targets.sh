#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
adapter="$ROOT/installer/adapters/windows-list-targets.ps1"
fixture="$ROOT/installer/tests/windows-disks.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

command -v pwsh >/dev/null 2>&1 || { printf 'error: PowerShell 7 is required for Windows adapter tests\n' >&2; exit 2; }
pwsh -NoProfile -NonInteractive -File "$adapter" -FixturePath "$fixture" > "$work/inventory.json"

jq -e '
  .schema == 1 and (.targets | length == 3) and
  ([.targets[] | select(.path == "\\\\.\\PhysicalDrive0" and .system == true and .removable == false)] | length == 1) and
  ([.targets[] | select(.path == "\\\\.\\PhysicalDrive2" and .model == "Bedrock Test USB" and .system == false and .removable == true and .mounted == false)] | length == 1) and
  ([.targets[] | select(.path == "\\\\.\\PhysicalDrive3" and .mounted == true)] | length == 1) and
  ([.targets[].id] | unique | length == 3)
' "$work/inventory.json" >/dev/null

safe_id=$(jq -r '.targets[] | select(.path == "\\\\.\\PhysicalDrive2") | .id' "$work/inventory.json")
sh "$ROOT/installer/core/validate-target-selection.sh" "$work/inventory.json" "$safe_id" \
  'ERASE Bedrock Test USB — \\.\PhysicalDrive2 — 17179869184' >/dev/null

jq 'map(.is_boot = false | .is_system = false)' "$fixture" > "$work/unknown-system.json"
pwsh -NoProfile -NonInteractive -File "$adapter" -FixturePath "$work/unknown-system.json" > "$work/unknown-inventory.json"
jq -e '[.targets[] | select(.system != true)] | length == 0' "$work/unknown-inventory.json" >/dev/null

printf 'Bedrock Windows target enumeration tests passed.\n'
