#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator="$ROOT/os/tests/validate-vm-guest-acceptance.sh"
fixture="$ROOT/os/tests/vm-guest-acceptance.example.json"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
image=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cp "$fixture" "$work/linux.json"
jq '.role="windows" | .session_id="22222222-2222-4222-8222-222222222222" | .guest_media_sha256="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" | .vm.name="acceptance-windows"' "$fixture" > "$work/windows.json"
run() { BEDROCK_VM_ACCEPTANCE_TEST_MODE=1 "$validator" "$image" "$work/linux.json" "$work/windows.json"; }
run >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail "$validator" "$image" "$work/linux.json" "$work/windows.json"
jq '.checks.snapshot_restore_completed=false' "$work/windows.json" > "$work/bad.json"; mv "$work/bad.json" "$work/windows.json"; must_fail run
jq '.role="windows" | .session_id="22222222-2222-4222-8222-222222222222" | .guest_media_sha256="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" | .vm.name="acceptance-windows"' "$fixture" > "$work/windows.json"
jq '.integrity.restored_sha256=.integrity.mutated_sha256' "$work/windows.json" > "$work/bad.json"; mv "$work/bad.json" "$work/windows.json"; must_fail run
jq '.role="windows" | .session_id="22222222-2222-4222-8222-222222222222" | .guest_media_sha256="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" | .vm.name="acceptance-windows"' "$fixture" > "$work/windows.json"
jq '.session_id="11111111-1111-4111-8111-111111111111"' "$work/windows.json" > "$work/bad.json"; mv "$work/bad.json" "$work/windows.json"; must_fail run
jq '.role="windows" | .session_id="22222222-2222-4222-8222-222222222222" | .guest_media_sha256="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" | .vm.name="acceptance-windows" | .unexpected="notes"' "$fixture" > "$work/windows.json"; must_fail run
cp "$fixture" "$work/windows.json"; must_fail run
jq '.privacy.guest_addresses_included=true' "$work/linux.json" > "$work/bad.json"; mv "$work/bad.json" "$work/linux.json"; must_fail run
printf 'VM guest acceptance contract tests passed.\n'
