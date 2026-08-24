#!/bin/sh
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
LC_ALL=C
export PATH LC_ALL
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
[ "$#" -eq 1 ] || { printf 'usage: %s REQUEST.json\n' "$0" >&2; exit 2; }
[ "${BEDROCK_INSTALLER_TEST_MODE:-0}" != 1 ] || {
  printf 'error: the physical system writer cannot run in installer test mode\n' >&2
  exit 1
}
[ "$(id -u)" -eq 0 ] || { printf 'error: protected system installation requires root\n' >&2; exit 1; }

request=$1
writer=/usr/lib/bedrock/bedrock-system-writer
finalizer="$ROOT/os/installer/finalize-protected-layout.sh"
package_dir=/run/live/medium/bedrock
image="$package_dir/bedrock-os-amd64.raw"
checksum="$package_dir/bedrock-os-amd64.raw.sha256"

for tool in jq sha256sum stat; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 2; }
done
for file in "$request" "$writer" "$finalizer" "$image" "$checksum"; do
  [ -f "$file" ] && [ ! -L "$file" ] || { printf 'error: protected writer component is missing or indirect\n' >&2; exit 1; }
done
for component in "$writer" "$finalizer"; do
  component_mode=$(stat -c %a "$component")
  [ "$(stat -c %u "$component")" -eq 0 ] && [ $((0$component_mode & 022)) -eq 0 ] || {
    printf 'error: protected installer component ownership or permissions are unsafe\n' >&2
    exit 1
  }
done
[ -x "$writer" ] || { printf 'error: protected system writer is not executable\n' >&2; exit 1; }

preflight=$(sh "$ROOT/os/installer/preflight-protected-install.sh" "$request")
printf '%s' "$preflight" | jq -e '
  .schema == 1 and .preflight_complete == true and .ready_for_writer == false
' >/dev/null || { printf 'error: protected system installation preflight did not complete\n' >&2; exit 1; }

target=$(jq -er '.target_snapshot.path | select(type == "string")' "$request")
capacity=$(jq -er '.target_snapshot.size_bytes | select(type == "number" and floor == . and . > 0)' "$request")
image_size=$(wc -c < "$image" | tr -d ' ')
expected_hash=$(awk 'NF == 2 {print $1; exit}' "$checksum")
printf '%s' "$expected_hash" | grep -Eq '^[0-9a-f]{64}$' || {
  printf 'error: packaged installation checksum is invalid\n' >&2
  exit 1
}

result=$($writer "$image" "$target" "$capacity" "$image_size" "$expected_hash")
printf '%s' "$result" | jq -e '
  .schema == 1 and .raw_write_complete == true and .reread_verified == true and
  (.device_major | type == "number" and floor == . and . >= 0) and
  (.device_minor | type == "number" and floor == . and . >= 0) and
  .layout_finalized == false
' >/dev/null || { printf 'error: protected raw writer returned an invalid result\n' >&2; exit 1; }

device_major=$(printf '%s' "$result" | jq -r .device_major)
device_minor=$(printf '%s' "$result" | jq -r .device_minor)
final=$($finalizer "$device_major" "$device_minor" "$capacity")
printf '%s' "$final" | jq -e '
  .schema == 1 and .layout_finalized == true and .gpt_verified == true and
  .persistent_state_checked == true and (.persistent_state_expanded | type == "boolean")
' >/dev/null || { printf 'error: protected layout finalizer returned an invalid result\n' >&2; exit 1; }

jq -n -c --argjson raw "$result" --argjson final "$final" '
  {
    schema: 1,
    installation_complete: true,
    raw_write_complete: $raw.raw_write_complete,
    reread_verified: $raw.reread_verified,
    layout_finalized: $final.layout_finalized,
    gpt_verified: $final.gpt_verified,
    persistent_state_checked: $final.persistent_state_checked,
    persistent_state_expanded: $final.persistent_state_expanded
  }
'
