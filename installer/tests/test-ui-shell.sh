#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ui="$ROOT/installer/ui"
for file in index.html styles.css app.js; do [ -s "$ui/$file" ] || { printf 'error: installer UI file is missing: %s\n' "$file" >&2; exit 1; }; done
node --check "$ui/app.js"
grep -q 'bedrock://installer-progress' "$ui/app.js"
grep -q 'Rereading and verifying media' "$ui/app.js"
grep -q 'state.image.sizeBytes' "$ui/app.js"
grep -q 'choose_and_verify_image' "$ui/app.js"
grep -q 'list_targets' "$ui/app.js"
grep -q 'write_verified_image' "$ui/app.js"
grep -q 'event.target.value !== state.phrase' "$ui/app.js"
grep -q 'No drive is written until its full name is confirmed' "$ui/index.html"
grep -q 'aria-label="Explain confirmation"' "$ui/index.html"
if grep -Eq '\b(dd|diskutil|Get-Disk)\b' "$ui/app.js"; then
  printf 'error: installer UI bypasses the secure desktop bridge\n' >&2
  exit 1
fi
printf 'Bedrock graphical installer shell contract is valid.\n'
