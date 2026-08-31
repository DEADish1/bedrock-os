#!/bin/sh
set -eu

[ "$#" -eq 3 ] || { printf 'usage: %s BEDROCK_IMAGE_SHA256 LINUX.json WINDOWS.json\n' "$0" >&2; exit 2; }
image_sha=$1
linux=$2
windows=$3
printf '%s' "$image_sha" | grep -Eq '^[0-9a-f]{64}$' || { printf 'error: expected Bedrock image SHA-256 is invalid\n' >&2; exit 1; }
[ "$linux" != "$windows" ] && [ ! "$linux" -ef "$windows" ] || { printf 'error: Linux and Windows require distinct report files\n' >&2; exit 1; }
if [ "${BEDROCK_VM_ACCEPTANCE_TEST_MODE:-0}" = 1 ]; then required_mode=fixture; else required_mode=physical; fi
validate() {
  role=$1
  report=$2
  [ -f "$report" ] && [ ! -L "$report" ] || { printf 'error: VM acceptance report is missing or indirect: %s\n' "$report" >&2; exit 1; }
  [ "$(stat -c %s "$report")" -le 16384 ] || { printf 'error: VM acceptance report is too large\n' >&2; exit 1; }
  jq -e --arg role "$role" --arg mode "$required_mode" --arg image "$image_sha" '
    (keys|sort)==(["bedrock_image_sha256","captured_at","checks","guest_media_sha256","integrity","mode","privacy","role","schema","session_id","vm"]|sort) and
    .schema==1 and .mode==$mode and .role==$role and .bedrock_image_sha256==$image and
    (.captured_at|type=="string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (.session_id|type=="string" and test("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")) and
    (.guest_media_sha256|type=="string" and test("^[0-9a-f]{64}$")) and
    (.vm|keys|sort)==(["memory_mib","name","vcpus"]|sort) and
    .vm.name==("acceptance-"+$role) and (.vm.vcpus|type=="number" and floor==. and .>=2 and .<=256) and
    (.vm.memory_mib|type=="number" and floor==. and .>=2048 and .<=1048576) and
    (.checks|keys|sort)==(["assigned_resources_verified","browser_console_ready","guest_agent_ready","guest_reboot_persisted","host_reboot_persisted","installation_completed","kvm_acceleration","network_ready","snapshot_created","snapshot_restore_completed","tpm2_persistent","uefi_secure_boot"]|sort) and
    all(.checks[]; .==true) and
    (.integrity|keys|sort)==(["baseline_sha256","mutated_sha256","restored_sha256"]|sort) and
    all(.integrity[]; type=="string" and test("^[0-9a-f]{64}$")) and
    .integrity.baseline_sha256==.integrity.restored_sha256 and .integrity.mutated_sha256!=.integrity.baseline_sha256 and
    .privacy=={guest_addresses_included:false,guest_credentials_included:false,guest_hostnames_included:false,serial_numbers_included:false,reviewed:true}
  ' "$report" >/dev/null || { printf 'error: %s VM acceptance report is incomplete, unsafe, or not %s mode\n' "$role" "$required_mode" >&2; exit 1; }
}
validate linux "$linux"
validate windows "$windows"
[ "$(jq -r .session_id "$linux")" != "$(jq -r .session_id "$windows")" ] || { printf 'error: guest reports must use distinct sessions\n' >&2; exit 1; }
[ "$(jq -r .guest_media_sha256 "$linux")" != "$(jq -r .guest_media_sha256 "$windows")" ] || { printf 'error: Linux and Windows installation media must be distinct\n' >&2; exit 1; }
printf 'Bedrock Linux and Windows VM guest acceptance bundle is valid for image %s.\n' "$image_sha"
