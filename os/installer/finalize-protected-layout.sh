#!/bin/sh
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
LC_ALL=C
export PATH LC_ALL
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ "$#" -eq 3 ] || { printf 'usage: %s DEVICE_MAJOR DEVICE_MINOR CAPACITY\n' "$0" >&2; exit 2; }
[ "${BEDROCK_INSTALLER_TEST_MODE:-0}" != 1 ] || {
  printf 'error: protected layout finalization cannot run in installer test mode\n' >&2
  exit 1
}
[ "$(id -u)" -eq 0 ] || { printf 'error: protected layout finalization requires root\n' >&2; exit 1; }

major=$1
minor=$2
capacity=$3
case $major:$minor:$capacity in
  *[!0-9:]*|:*|*::*|*:) printf 'error: protected device identity is invalid\n' >&2; exit 1 ;;
esac
[ "${#capacity}" -le 19 ] && [ "$capacity" -gt 0 ] && \
  [ "$major" -le 1048575 ] && [ "$minor" -le 1048575 ] || {
  printf 'error: protected device identity or capacity is out of range\n' >&2
  exit 1
}

if [ "$SCRIPT_DIR" = /usr/lib/bedrock/installer ]; then
  layout=/usr/share/bedrock/installer/bedrock-amd64.json
else
  ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
  layout="$ROOT/os/layout/bedrock-amd64.json"
fi
for tool in blockdev e2fsck jq lsblk mknod readlink resize2fs sgdisk sync udevadm; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 2; }
done
[ -f "$layout" ] && [ ! -L "$layout" ] || { printf 'error: canonical layout is missing or indirect\n' >&2; exit 1; }

state_name=$(jq -er '.partitions[] | select(.number == 8 and .role == "persistent-state" and .filesystem == "ext4" and .grow == true and .mutable == true) | .name' "$layout")
state_type=$(jq -er '.partitions[] | select(.number == 8) | .type_guid | ascii_upcase | select(test("^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"))' "$layout")
[ "$state_name" = bedrock-state ] || { printf 'error: canonical persistent-state layout is unexpected\n' >&2; exit 1; }

disk_sysfs=$(readlink -f "/sys/dev/block/$major:$minor")
[ -d "$disk_sysfs" ] && [ ! -f "$disk_sysfs/partition" ] || {
  printf 'error: protected identity is not a whole Linux disk\n' >&2
  exit 1
}

umask 077
work=$(mktemp -d /dev/bedrock-install.XXXXXX)
cleanup() {
  rm -f "$work/state" "$work/target"
  rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
target_node="$work/target"
mknod "$target_node" b "$major" "$minor"
[ "$(blockdev --getsize64 "$target_node")" -eq "$capacity" ] || {
  printf 'error: protected disk capacity changed before layout finalization\n' >&2
  exit 1
}
if lsblk -nr -o MOUNTPOINT "$target_node" | grep -Eq '[^[:space:]]'; then
  printf 'error: protected system disk became mounted before layout finalization\n' >&2
  exit 1
fi

state_info=$(sgdisk --info=8 "$target_node")
state_start=$(printf '%s\n' "$state_info" | awk '/First sector:/{print $3}')
state_old_sectors=$(printf '%s\n' "$state_info" | awk '/Partition size:/{print $3}')
state_guid=$(printf '%s\n' "$state_info" | awk '/Partition unique GUID:/{print $4}')
printf '%s' "$state_start:$state_old_sectors:$state_guid" | grep -Eq '^[0-9]+:[0-9]+:[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' || {
  printf 'error: persistent-state partition identity is invalid\n' >&2
  exit 1
}

sgdisk -e "$target_node" >/dev/null
sgdisk --delete=8 --new="8:${state_start}:0" --typecode="8:${state_type}" \
  --change-name="8:${state_name}" --partition-guid="8:${state_guid}" "$target_node" >/dev/null
sgdisk --verify "$target_node" >/dev/null
state_new_sectors=$(sgdisk --info=8 "$target_node" | awk '/Partition size:/{print $3}')
[ "$state_new_sectors" -ge "$state_old_sectors" ] || {
  printf 'error: persistent-state partition became smaller\n' >&2
  exit 1
}

sync
blockdev --flushbufs "$target_node"
reread_attempt=1
while ! blockdev --rereadpt "$target_node" 2>/dev/null; do
  [ "$reread_attempt" -lt 10 ] || {
    printf 'error: kernel kept the finalized system-disk partition table busy\n' >&2
    exit 1
  }
  udevadm settle --timeout=5
  sleep 1
  reread_attempt=$((reread_attempt + 1))
done
udevadm settle --timeout=30

state_identity=
state_count=0
for candidate in "$disk_sysfs"/*; do
  [ -f "$candidate/partition" ] || continue
  [ "$(cat "$candidate/partition")" = 8 ] || continue
  [ -f "$candidate/dev" ] || continue
  state_identity=$(cat "$candidate/dev")
  state_count=$((state_count + 1))
done
[ "$state_count" -eq 1 ] && printf '%s' "$state_identity" | grep -Eq '^[0-9]+:[0-9]+$' || {
  printf 'error: expanded persistent-state device identity is missing or ambiguous\n' >&2
  exit 1
}
state_major=${state_identity%:*}
state_minor=${state_identity#*:}
state_node="$work/state"
mknod "$state_node" b "$state_major" "$state_minor"
[ "$(blockdev --getsz "$state_node")" -eq "$state_new_sectors" ] || {
  printf 'error: persistent-state device size differs from the finalized GPT\n' >&2
  exit 1
}
if lsblk -nr -o MOUNTPOINT "$state_node" | grep -Eq '[^[:space:]]'; then
  printf 'error: persistent-state partition became mounted during finalization\n' >&2
  exit 1
fi

e2fsck -f -y "$state_node" >/dev/null 2>&1
resize2fs "$state_node" >/dev/null 2>&1
e2fsck -f -n "$state_node" >/dev/null 2>&1
sync
blockdev --flushbufs "$state_node"

sgdisk --verify "$target_node" >/dev/null
jq -c '.partitions[]' "$layout" | while IFS= read -r partition; do
  number=$(printf '%s' "$partition" | jq -r .number)
  expected_name=$(printf '%s' "$partition" | jq -r .name)
  expected_type=$(printf '%s' "$partition" | jq -r .type_guid | tr '[:lower:]' '[:upper:]')
  info=$(sgdisk --info="$number" "$target_node")
  printf '%s\n' "$info" | grep -F "Partition name: '$expected_name'" >/dev/null || exit 1
  printf '%s\n' "$info" | grep -F "Partition GUID code: $expected_type" >/dev/null || exit 1
done || { printf 'error: final Bedrock partition contract differs from the canonical layout\n' >&2; exit 1; }
sync
blockdev --flushbufs "$target_node"

state_expanded=false
[ "$state_new_sectors" -eq "$state_old_sectors" ] || state_expanded=true
jq -n -c --argjson expanded "$state_expanded" '
  {
    schema: 1,
    layout_finalized: true,
    gpt_verified: true,
    persistent_state_checked: true,
    persistent_state_expanded: $expanded
  }
'
