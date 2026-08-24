#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
[ "$#" -eq 1 ] || { printf 'usage: %s REQUEST.json\n' "$0" >&2; exit 2; }
[ "${BEDROCK_INSTALLER_TEST_MODE:-0}" != 1 ] || {
  printf 'error: the physical system writer cannot run in installer test mode\n' >&2
  exit 1
}
[ "$(id -u)" -eq 0 ] || { printf 'error: protected system installation requires root\n' >&2; exit 1; }

request=$1
writer=/usr/lib/bedrock/bedrock-system-writer
package_dir=/run/live/medium/bedrock
image="$package_dir/bedrock-os-amd64.raw"
checksum="$package_dir/bedrock-os-amd64.raw.sha256"

for tool in jq sha256sum stat; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 2; }
done
for file in "$request" "$writer" "$image" "$checksum"; do
  [ -f "$file" ] && [ ! -L "$file" ] || { printf 'error: protected writer component is missing or indirect\n' >&2; exit 1; }
done
writer_mode=$(stat -c %a "$writer")
[ -x "$writer" ] && [ "$(stat -c %u "$writer")" -eq 0 ] && [ $((0$writer_mode & 022)) -eq 0 ] || {
  printf 'error: protected system writer ownership or permissions are unsafe\n' >&2
  exit 1
}

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
  .layout_finalized == false
' >/dev/null || { printf 'error: protected raw writer returned an invalid result\n' >&2; exit 1; }
printf '%s\n' "$result"
