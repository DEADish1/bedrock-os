#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator="$root/os/tests/validate-restore-drill-report.sh"
fixture="$root/os/tests/restore-drill-report.example.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"$validator" "$fixture" >/dev/null
jq '.scenarios.files.restored_sha256 = ("d" * 64)' "$fixture" > "$work/bad-hash.json"
if "$validator" "$work/bad-hash.json" >/dev/null 2>&1; then exit 1; fi
jq '.scenarios.failed_system_drive.original_drive_untouched = false' "$fixture" > "$work/bad-drive.json"
if "$validator" "$work/bad-drive.json" >/dev/null 2>&1; then exit 1; fi
jq '.scenarios.vm_data.status = "pending"' "$fixture" > "$work/pending.json"
if "$validator" "$work/pending.json" >/dev/null 2>&1; then exit 1; fi

printf 'Bedrock restore drill evidence validation tests passed.\n'
