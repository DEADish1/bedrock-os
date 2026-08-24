#!/bin/sh
set -eu

for tool in e2fsck jq mkfs.ext4 resize2fs sgdisk sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'Bedrock installation-image simulator test skipped: %s unavailable.\n' "$tool"
    exit 0
  }
done

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
simulator="$ROOT/os/installer/simulate-install-image.sh"
planner="$ROOT/os/installer/create-install-plan.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/targets"

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

source_image="$work/bedrock-test.raw"
truncate -s 67108864 "$source_image"
sgdisk --zap-all "$source_image" >/dev/null
jq -c '.partitions[]' "$work/layout.json" | while IFS= read -r partition; do
  number=$(printf '%s' "$partition" | jq -r .number)
  name=$(printf '%s' "$partition" | jq -r .name)
  type=$(printf '%s' "$partition" | jq -r .type_guid)
  bytes=$(printf '%s' "$partition" | jq -r '.size_bytes // 0')
  if [ "$bytes" -gt 0 ]; then end="+$((bytes / 512))S"; else end=0; fi
  sgdisk --new="$number:0:$end" --typecode="$number:$type" --change-name="$number:$name" "$source_image" >/dev/null
done
sgdisk --verify "$source_image" >/dev/null

state_start=$(sgdisk --info=8 "$source_image" | awk '/First sector:/{print $3}')
state_sectors=$(sgdisk --info=8 "$source_image" | awk '/Partition size:/{print $3}')
truncate -s "$((state_sectors * 512))" "$work/state.img"
mkfs.ext4 -q -F -L bedrock-state "$work/state.img"
dd if="$work/state.img" of="$source_image" bs=512 seek="$state_start" conv=fsync,notrunc,sparse status=none
printf 'BEDROCK-ROOT-A-TEST' | dd of="$source_image" bs=1 seek=$((6 * 1048576)) conv=notrunc status=none
sha256sum "$source_image" | (cd "$work" && sed 's#  .*/#  #' > bedrock-test.raw.sha256)

target="$work/targets/system.raw"
truncate -s 83886080 "$target"
jq -n --arg path /dev/test-system '{
  schema:1,generated_at:"2026-08-24T00:00:00Z",targets:[{
    id:"linux:test-system",path:$path,model:"Disposable System Image",size_bytes:83886080,
    removable:false,system:false,mounted:false,read_only:false
  }]
' > "$work/inventory.json"
confirmation='INSTALL BEDROCK — Disposable System Image — /dev/test-system — 83886080'
BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_LAYOUT="$work/layout.json" \
  sh "$planner" "$work/inventory.json" linux:test-system "$confirmation" > "$work/plan.json"

BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_TARGET_DIR="$work/targets" BEDROCK_TEST_LAYOUT="$work/layout.json" \
  sh "$simulator" "$source_image" "$work/bedrock-test.raw.sha256" "$work/plan.json" "$target" >/dev/null
BEDROCK_INSTALLER_TEST_MODE=1 sh "$ROOT/os/scripts/verify-disk-image.sh" "$target" "$work/layout.json" >/dev/null
state_grown=$(sgdisk --info=8 "$target" | awk '/Partition size:/{print $3}')
[ "$state_grown" -gt "$state_sectors" ] || { printf 'error: simulator did not grow persistent state\n' >&2; exit 1; }
marker=$(dd if="$target" bs=1 skip=$((6 * 1048576)) count=19 status=none)
[ "$marker" = 'BEDROCK-ROOT-A-TEST' ] || { printf 'error: simulator changed fixed system content\n' >&2; exit 1; }

cp "$target" "$work/targets/interrupted.raw"
if BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_TARGET_DIR="$work/targets" BEDROCK_TEST_LAYOUT="$work/layout.json" BEDROCK_TEST_INTERRUPT_AFTER_WRITE=1 \
  sh "$simulator" "$source_image" "$work/bedrock-test.raw.sha256" "$work/plan.json" "$work/targets/interrupted.raw" >/dev/null 2>&1; then
  printf 'error: interrupted simulated installation was accepted\n' >&2
  exit 1
fi

truncate -s 83886080 "$work/targets/corrupt.raw"
if BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_TARGET_DIR="$work/targets" BEDROCK_TEST_LAYOUT="$work/layout.json" BEDROCK_TEST_CORRUPT_AFTER_WRITE=1 \
  sh "$simulator" "$source_image" "$work/bedrock-test.raw.sha256" "$work/plan.json" "$work/targets/corrupt.raw" >/dev/null 2>&1; then
  printf 'error: corrupted simulated installation was accepted\n' >&2
  exit 1
fi

if BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_TARGET_DIR="$work/targets" BEDROCK_TEST_LAYOUT="$work/layout.json" \
  sh "$simulator" "$source_image" "$work/bedrock-test.raw.sha256" "$work/plan.json" "$work/outside.raw" >/dev/null 2>&1; then
  printf 'error: simulator accepted a target outside the declared test directory\n' >&2
  exit 1
fi

printf 'Bedrock disposable installation-image simulation passed.\n'
