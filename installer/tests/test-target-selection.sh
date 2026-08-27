#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator="$ROOT/installer/core/validate-target-selection.sh"
inventory="$ROOT/installer/tests/targets.json"

pass='ERASE Bedrock Test USB — /dev/disk9 — 17179869184'
sh "$validator" "$inventory" usb-safe "$pass" | jq -e '.id == "usb-safe"' >/dev/null

for case in \
  'system-disk|ERASE Internal SSD — /dev/disk0 — 512110190592' \
  'mounted-usb|ERASE Mounted USB — /dev/disk8 — 17179869184' \
  'tiny-usb|ERASE Tiny USB — /dev/disk7 — 4294967296' \
  'missing|ERASE Missing — /dev/disk6 — 17179869184' \
  'usb-safe|ERASE the selected drive'; do
  id=${case%%|*}
  phrase=${case#*|}
  if sh "$validator" "$inventory" "$id" "$phrase" >/dev/null 2>&1; then
    printf 'error: unsafe target case was accepted: %s\n' "$id" >&2
    exit 1
  fi
done

printf 'Bedrock installer target-selection safety tests passed.\n'
