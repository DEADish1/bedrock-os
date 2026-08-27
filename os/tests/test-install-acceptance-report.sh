#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator="$ROOT/os/tests/validate-install-acceptance-report.sh"
fixture="$ROOT/os/tests/install-acceptance-report.example.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

BEDROCK_ALLOW_FIXTURE_INSTALL_REPORT=1 sh "$validator" "$fixture" >/dev/null
if sh "$validator" "$fixture" >/dev/null 2>&1; then
  printf 'error: fixture system-install report passed as physical evidence\n' >&2
  exit 1
fi

reject() {
  label=$1 filter=$2
  jq "$filter" "$fixture" > "$work/$label.json"
  if BEDROCK_ALLOW_FIXTURE_INSTALL_REPORT=1 sh "$validator" "$work/$label.json" >/dev/null 2>&1; then
    printf 'error: system-install validator accepted %s evidence\n' "$label" >&2
    exit 1
  fi
}
reject incomplete-check '.checks.reread_verified = false'
reject non-disposable '.target.disposable = false'
reject short-disk '.target.size_bytes = 1024'
reject serial-number '.serial_number = "private"'
reject username '.username = "private"'
reject unknown-field '.unexpected = true'

jq '.mode = "physical" | .target.path = "/dev/nvme0n1"' "$fixture" > "$work/physical.json"
sh "$validator" "$work/physical.json" >/dev/null

printf 'Bedrock system-install acceptance-report tests passed.\n'
