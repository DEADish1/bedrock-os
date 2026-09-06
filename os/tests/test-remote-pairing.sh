#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-remote-pairing"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
server=$(printf server | sha256sum | awk '{print $1}'); client=$(printf client | sha256sum | awk '{print $1}')
printf '%s\n' "$server" > "$work/server-public-key"
id=12345678-1234-4123-8123-123456789abc code=BRK-ABCD-2345 boot=87654321-4321-4321-8321-cba987654321
run() { now=$1; shift; BEDROCK_PAIRING_TEST_MODE=1 BEDROCK_PAIRING_STATE_DIR="$work" BEDROCK_PAIRING_SERVER_KEY="$work/server-public-key" BEDROCK_PAIRING_TEST_BOOT_ID="$boot" BEDROCK_PAIRING_TEST_NOW="$now" BEDROCK_PAIRING_TEST_ID="$id" BEDROCK_PAIRING_TEST_CODE="$code" python3 "$tool" "$@"; }
run 100 request "$client" | jq -e --arg id "$id" --arg code "$code" '.pairing_id==$id and .manual_code==$code and .expires_seconds==600 and .qr.manual_code==$code' >/dev/null
! grep -q "$code" "$work/pairings.json"
if run 101 redeem "$id" "$code" "$client" >/dev/null 2>&1; then echo "unapproved pairing redeemed" >&2; exit 1; fi
run 102 approve "$id" "APPROVE REMOTE DEVICE $id" | jq -e '.status=="approved"' >/dev/null
run 103 redeem "$id" "$code" "$client" | jq -e '.status=="redeemed" and (.client_key_sha256|test("^[0-9a-f]{64}$"))' >/dev/null
if run 104 redeem "$id" "$code" "$client" >/dev/null 2>&1; then echo "pairing code replayed" >&2; exit 1; fi
id=22345678-1234-4123-8123-123456789abc code=BRK-EFGH-6789
run 200 request "$client" >/dev/null
run 201 approve "$id" "APPROVE REMOTE DEVICE $id" >/dev/null
if run 801 redeem "$id" "$code" "$client" >/dev/null 2>&1; then echo "expired pairing redeemed" >&2; exit 1; fi
id=32345678-1234-4123-8123-123456789abc code=BRK-JKLM-2345
run 900 request "$client" >/dev/null
run 901 approve "$id" "APPROVE REMOTE DEVICE $id" >/dev/null
boot=47654321-4321-4321-8321-cba987654321
if run 902 redeem "$id" "$code" "$client" >/dev/null 2>&1; then echo "pre-reboot pairing redeemed" >&2; exit 1; fi
printf 'Bedrock one-time remote pairing state tests passed.\n'
