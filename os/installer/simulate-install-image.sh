#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
[ "$#" -eq 4 ] || {
  printf 'usage: %s SOURCE.raw SOURCE.raw.sha256 PLAN.json TARGET.raw\n' "$0" >&2
  exit 2
}
[ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ] || {
  printf 'error: the installation simulator is available only in explicit test mode\n' >&2
  exit 1
}
: "${BEDROCK_TEST_TARGET_DIR:?test mode requires BEDROCK_TEST_TARGET_DIR}"
: "${BEDROCK_TEST_LAYOUT:?test mode requires BEDROCK_TEST_LAYOUT}"

source_image=$1
checksum_file=$2
plan=$3
target=$4
layout=$BEDROCK_TEST_LAYOUT

for tool in awk dd e2fsck jq resize2fs sgdisk sha256sum truncate; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 2; }
done
for file in "$source_image" "$checksum_file" "$plan" "$layout"; do
  [ -f "$file" ] && [ ! -L "$file" ] || { printf 'error: simulator input is missing or indirect\n' >&2; exit 1; }
done

test_root=$(CDPATH= cd -- "$BEDROCK_TEST_TARGET_DIR" && pwd)
target_parent=$(CDPATH= cd -- "$(dirname -- "$target")" && pwd)
[ "$target_parent" = "$test_root" ] && [ -f "$target" ] && [ ! -L "$target" ] || {
  printf 'error: simulator target must be a regular file directly inside the declared test directory\n' >&2
  exit 1
}
[ ! -b "$target" ] || { printf 'error: simulator refuses block devices\n' >&2; exit 1; }

layout_hash=$(sha256sum "$layout" | awk '{print $1}')
minimum=$(jq -er '.minimum_disk_bytes | select(type == "number" and floor == . and . > 0)' "$layout")
capacity=$(jq -er --arg hash "$layout_hash" '
  select(
    .schema == 1 and .operation == "install-bedrock-system" and
    .source == "packaged-signed-live-system" and
    .layout.sha256 == $hash and .layout.minimum_disk_bytes > 0 and
    .preserve_existing_data == false and
    .requires_fresh_inventory == true and
    .requires_exclusive_whole_disk == true and
    .ready_for_writer == false
  ) | .target.size_bytes | select(type == "number" and floor == .)
' "$plan") || { printf 'error: invalid or mismatched installation plan\n' >&2; exit 1; }

source_size=$(wc -c < "$source_image" | tr -d ' ')
target_size=$(wc -c < "$target" | tr -d ' ')
[ "$source_size" -eq "$minimum" ] || { printf 'error: source image size differs from the planned layout\n' >&2; exit 1; }
[ "$target_size" -eq "$capacity" ] && [ "$target_size" -ge "$source_size" ] || {
  printf 'error: simulator target capacity differs from the selected disk\n' >&2
  exit 1
}

expected_hash=$(awk 'NF == 2 {print $1; exit}' "$checksum_file")
expected_name=$(awk 'NF == 2 {print $2; exit}' "$checksum_file" | sed 's/^\*//')
[ "$expected_name" = "$(basename -- "$source_image")" ] && printf '%s' "$expected_hash" | grep -Eq '^[0-9a-f]{64}$' || {
  printf 'error: invalid source checksum manifest\n' >&2
  exit 1
}
[ "$(sha256sum "$source_image" | awk '{print $1}')" = "$expected_hash" ] || {
  printf 'error: source installation image failed checksum verification\n' >&2
  exit 1
}
BEDROCK_INSTALLER_TEST_MODE=1 sh "$ROOT/os/scripts/verify-disk-image.sh" "$source_image" "$layout" >/dev/null

dd if="$source_image" of="$target" bs=1048576 conv=fsync,notrunc,sparse status=none || {
  printf 'error: simulated installation write was interrupted or incomplete\n' >&2
  exit 1
}
[ "${BEDROCK_TEST_INTERRUPT_AFTER_WRITE:-0}" != 1 ] || {
  printf 'error: simulated installation was interrupted; the target must be rewritten from the beginning\n' >&2
  exit 1
}
[ "${BEDROCK_TEST_CORRUPT_AFTER_WRITE:-0}" != 1 ] || printf 'x' | dd of="$target" bs=1 seek=4096 conv=notrunc status=none

written_hash=$(dd if="$target" bs=1048576 count=$(( (source_size + 1048575) / 1048576 )) status=none | head -c "$source_size" | sha256sum | awk '{print $1}')
[ "$written_hash" = "$expected_hash" ] || {
  printf 'error: simulated installed image failed reread verification\n' >&2
  exit 1
}

state_start=$(sgdisk --info=8 "$target" | awk '/First sector:/{print $3}')
state_old_sectors=$(sgdisk --info=8 "$target" | awk '/Partition size:/{print $3}')
state_guid=$(sgdisk --info=8 "$target" | awk '/Partition unique GUID:/{print $4}')
state_type=$(jq -r '.partitions[] | select(.number == 8) | .type_guid' "$layout")
state_name=$(jq -r '.partitions[] | select(.number == 8) | .name' "$layout")
[ -n "$state_start" ] && [ -n "$state_old_sectors" ] && [ -n "$state_guid" ] || {
  printf 'error: source state partition could not be identified\n' >&2
  exit 1
}

sgdisk -e "$target" >/dev/null
sgdisk --delete=8 --new="8:${state_start}:0" --typecode="8:${state_type}" \
  --change-name="8:${state_name}" --partition-guid="8:${state_guid}" "$target" >/dev/null
sgdisk --verify "$target" >/dev/null
state_new_sectors=$(sgdisk --info=8 "$target" | awk '/Partition size:/{print $3}')
[ "$state_new_sectors" -gt "$state_old_sectors" ] || {
  printf 'error: persistent state partition did not grow\n' >&2
  exit 1
}

work=$(mktemp -d)
cleanup() { rm -f "$work/state.img"; rmdir "$work" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
state_image="$work/state.img"
dd if="$target" of="$state_image" bs=512 skip="$state_start" count="$state_old_sectors" conv=sparse status=none
truncate -s "$((state_new_sectors * 512))" "$state_image"
e2fsck -f -y "$state_image" >/dev/null 2>&1
resize2fs "$state_image" >/dev/null 2>&1
e2fsck -f -n "$state_image" >/dev/null 2>&1
dd if="$state_image" of="$target" bs=512 seek="$state_start" conv=fsync,notrunc,sparse status=none

BEDROCK_INSTALLER_TEST_MODE=1 sh "$ROOT/os/scripts/verify-disk-image.sh" "$target" "$layout" >/dev/null
printf 'Simulated Bedrock system installation written, expanded, and verified: %s\n' "$target"
