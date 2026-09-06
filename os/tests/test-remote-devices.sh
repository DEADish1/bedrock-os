#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd); pairing="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-remote-pairing"; devices="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-remote-devices"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
server=$(printf server | sha256sum | awk '{print $1}'); client=$(printf client | sha256sum | awk '{print $1}'); printf '%s\n' "$server" > "$work/server-public-key"
pair=12345678-1234-4123-8123-123456789abc; device=42345678-1234-4123-8123-123456789abc; code=BRK-ABCD-2345; boot=87654321-4321-4321-8321-cba987654321
envs="BEDROCK_PAIRING_TEST_MODE=1 BEDROCK_PAIRING_STATE_DIR=$work BEDROCK_PAIRING_TEST_WALL_NOW=1000"
env $envs BEDROCK_PAIRING_SERVER_KEY="$work/server-public-key" BEDROCK_PAIRING_TEST_BOOT_ID="$boot" BEDROCK_PAIRING_TEST_NOW=1 BEDROCK_PAIRING_TEST_ID="$pair" BEDROCK_PAIRING_TEST_DEVICE_ID="$device" BEDROCK_PAIRING_TEST_CODE="$code" python3 "$pairing" request "$client" >/dev/null
env $envs BEDROCK_PAIRING_SERVER_KEY="$work/server-public-key" BEDROCK_PAIRING_TEST_BOOT_ID="$boot" BEDROCK_PAIRING_TEST_NOW=2 python3 "$pairing" approve "$pair" "APPROVE REMOTE DEVICE $pair" >/dev/null
env $envs BEDROCK_PAIRING_SERVER_KEY="$work/server-public-key" BEDROCK_PAIRING_TEST_BOOT_ID="$boot" BEDROCK_PAIRING_TEST_NOW=3 BEDROCK_PAIRING_TEST_DEVICE_ID="$device" python3 "$pairing" redeem "$pair" "$code" "$client" >/dev/null
env $envs python3 "$devices" list | jq -e --arg id "$device" '(.devices|length)==1 and .devices[0].id==$id and .devices[0].name=="New device" and .devices[0].revoked==false and (.devices[0] | has("public_key") | not)' >/dev/null
env $envs python3 "$devices" rename "$device" "Office laptop" | jq -e '.action=="rename"' >/dev/null
env $envs python3 "$devices" expire "$device" 2000 "EXPIRE REMOTE DEVICE $device AT 2000" | jq -e '.action=="expire"' >/dev/null
env $envs BEDROCK_PAIRING_TEST_WALL_NOW=2001 python3 "$devices" list | jq -e '.["devices"][0].expired==true' >/dev/null
env $envs python3 "$devices" revoke "$device" "REVOKE REMOTE DEVICE $device" | jq -e '.action=="revoke"' >/dev/null
if env $envs python3 "$devices" revoke "$device" "REVOKE REMOTE DEVICE $device" >/dev/null 2>&1; then echo "device revoked twice" >&2; exit 1; fi
jq -e '.devices[0].name=="Office laptop" and .devices[0].expires_unix==2000 and .devices[0].revoked==true and (.devices[0].public_key|test("^[0-9a-f]{64}$"))' "$work/pairings.json" >/dev/null
printf 'Bedrock remote per-device identity lifecycle tests passed.\n'
