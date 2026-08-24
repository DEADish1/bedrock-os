#!/bin/sh
set -eu

[ "${BEDROCK_RUN_LOOP_INSTALL_TEST:-0}" = 1 ] || {
  printf 'Bedrock protected loop-install test skipped: explicit loop-test gate is disabled.\n'
  exit 0
}
[ "$(uname -s)" = Linux ] && [ "$(id -u)" -eq 0 ] || {
  printf 'error: protected loop-install test requires root on Linux\n' >&2
  exit 1
}

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
for tool in blockdev e2fsck jq losetup mkfs.ext4 modprobe readlink resize2fs rustc sgdisk sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: loop-install test requires %s\n' "$tool" >&2; exit 2; }
done

work=$(mktemp -d)
loop_device=
cleanup() {
  if [ -n "$loop_device" ]; then losetup -d "$loop_device" 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM
modprobe loop

jq '
  .minimum_disk_bytes = 67108864 |
  .partitions[0].size_bytes = 4194304 |
  .partitions[1].size_bytes = 8388608 |
  .partitions[2].size_bytes = 2097152 |
  .partitions[3].size_bytes = 1048576 |
  .partitions[4].size_bytes = 8388608 |
  .partitions[5].size_bytes = 2097152 |
  .partitions[6].size_bytes = 1048576 |
  .partitions[7].minimum_size_bytes = 8388608
' "$ROOT/os/layout/bedrock-amd64.json" > "$work/layout.json"

source_image="$work/source.raw"
target_image="$work/target.raw"
truncate -s 67108864 "$source_image"
truncate -s 83886080 "$target_image"
sgdisk --zap-all "$source_image" >/dev/null
jq -c '.partitions[]' "$work/layout.json" | while IFS= read -r partition; do
  number=$(printf '%s' "$partition" | jq -r .number)
  name=$(printf '%s' "$partition" | jq -r .name)
  type=$(printf '%s' "$partition" | jq -r .type_guid)
  bytes=$(printf '%s' "$partition" | jq -r '.size_bytes // 0')
  if [ "$bytes" -gt 0 ]; then end="+$((bytes / 512))S"; else end=0; fi
  sgdisk --new="$number:0:$end" --typecode="$number:$type" \
    --change-name="$number:$name" "$source_image" >/dev/null
done
sgdisk --verify "$source_image" >/dev/null

state_start=$(sgdisk --info=8 "$source_image" | awk '/First sector:/{print $3}')
state_old_sectors=$(sgdisk --info=8 "$source_image" | awk '/Partition size:/{print $3}')
truncate -s "$((state_old_sectors * 512))" "$work/state.img"
mkfs.ext4 -q -F -L bedrock-state "$work/state.img"
dd if="$work/state.img" of="$source_image" bs=512 seek="$state_start" conv=fsync,notrunc,sparse status=none
printf 'BEDROCK-PROTECTED-ROOT' | dd of="$source_image" bs=1 seek=$((6 * 1048576)) conv=notrunc status=none
source_size=$(wc -c < "$source_image" | tr -d ' ')
source_hash=$(sha256sum "$source_image" | awk '{print $1}')

BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER=I_ACCEPT_REAL_SYSTEM_DISK_DATA_LOSS \
BEDROCK_REQUIRE_PRODUCTION_TRUST=1 \
  sh "$ROOT/os/installer/build-protected-system-writer.sh" "$work/writer"

loop_device=$(losetup --find --show "$target_image")
case $loop_device in /dev/loop[0-9]*) ;; *) printf 'error: disposable target is not a loop device\n' >&2; exit 1 ;; esac
backing_file=$(cat "/sys/class/block/${loop_device##*/}/loop/backing_file")
[ "$(readlink -f "$backing_file")" = "$(readlink -f "$target_image")" ] || {
  printf 'error: loop device is not bound to the disposable test image\n' >&2
  exit 1
}
capacity=$(blockdev --getsize64 "$loop_device")
[ "$capacity" -eq 83886080 ] || { printf 'error: disposable loop capacity is unexpected\n' >&2; exit 1; }

raw_result=$("$work/writer" "$source_image" "$loop_device" "$capacity" "$source_size" "$source_hash")
printf '%s' "$raw_result" | jq -e '
  .schema == 1 and .raw_write_complete == true and .reread_verified == true and
  .layout_finalized == false and .device_major >= 0 and .device_minor >= 0
' >/dev/null
major=$(printf '%s' "$raw_result" | jq -r .device_major)
minor=$(printf '%s' "$raw_result" | jq -r .device_minor)

final_result=$(sh "$ROOT/os/installer/finalize-protected-layout.sh" "$major" "$minor" "$capacity")
printf '%s' "$final_result" | jq -e '
  .schema == 1 and .layout_finalized == true and .gpt_verified == true and
  .persistent_state_checked == true and .persistent_state_expanded == true
' >/dev/null

losetup -d "$loop_device"
loop_device=
BEDROCK_INSTALLER_TEST_MODE=1 sh "$ROOT/os/scripts/verify-disk-image.sh" "$target_image" "$work/layout.json" >/dev/null
state_new_sectors=$(sgdisk --info=8 "$target_image" | awk '/Partition size:/{print $3}')
[ "$state_new_sectors" -gt "$state_old_sectors" ] || { printf 'error: protected finalizer did not grow state\n' >&2; exit 1; }
marker=$(dd if="$target_image" bs=1 skip=$((6 * 1048576)) count=22 status=none)
[ "$marker" = BEDROCK-PROTECTED-ROOT ] || { printf 'error: protected finalizer changed fixed system content\n' >&2; exit 1; }

printf 'Bedrock protected writer/finalizer passed on a disposable loop-backed image.\n'
