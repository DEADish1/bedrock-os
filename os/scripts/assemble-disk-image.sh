#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
LAYOUT="$ROOT/os/layout/bedrock-amd64.json"

usage() {
  printf 'usage: %s COMPONENT_DIR OUTPUT.raw\n' "$0" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
components=$1
output=$2
for tool in jq mcopy mformat mmd mkfs.ext4 sgdisk; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }
done

for file in \
  bedrock-root-a.erofs bedrock-root-a.verity bedrock-root-a.verity-sig.json bedrock-a.efi \
  bedrock-root-b.erofs bedrock-root-b.verity bedrock-root-b.verity-sig.json bedrock-b.efi \
  systemd-bootx64.efi; do
  [ -s "$components/$file" ] || { printf 'error: missing component: %s\n' "$file" >&2; exit 1; }
done

minimum=$(jq -r '.minimum_disk_bytes' "$LAYOUT")
mkdir -p "$(dirname -- "$output")"
truncate -s "$minimum" "$output"
sgdisk --zap-all "$output" >/dev/null

jq -c '.partitions[]' "$LAYOUT" | while IFS= read -r partition; do
  number=$(printf '%s' "$partition" | jq -r '.number')
  name=$(printf '%s' "$partition" | jq -r '.name')
  type=$(printf '%s' "$partition" | jq -r '.type_guid')
  bytes=$(printf '%s' "$partition" | jq -r '.size_bytes // 0')
  if [ "$bytes" -gt 0 ]; then
    sectors=$((bytes / 512))
    end="+$sectors"S
  else
    end=0
  fi
  guid=$(printf '20000000-0000-4000-8000-%012d' "$number")
  sgdisk --new="$number:0:$end" --typecode="$number:$type" --change-name="$number:$name" --partition-guid="$number:$guid" "$output" >/dev/null
done
sgdisk --verify "$output" >/dev/null

partition_info() {
  sgdisk --info="$1" "$output"
}

partition_start() {
  partition_info "$1" | awk '/First sector:/{print $3}'
}

partition_sectors() {
  partition_info "$1" | awk '/Partition size:/{print $3}'
}

copy_component() {
  source=$1
  number=$2
  source_size=$(wc -c < "$source" | tr -d ' ')
  start=$(partition_start "$number")
  sectors=$(partition_sectors "$number")
  target_size=$((sectors * 512))
  [ "$source_size" -le "$target_size" ] || { printf 'error: %s exceeds partition %s\n' "$source" "$number" >&2; exit 1; }
  dd if="$source" of="$output" bs=512 seek="$start" conv=fsync,notrunc status=none
}

copy_component "$components/bedrock-root-a.erofs" 2
copy_component "$components/bedrock-root-a.verity" 3
copy_component "$components/bedrock-root-a.verity-sig.json" 4
copy_component "$components/bedrock-root-b.erofs" 5
copy_component "$components/bedrock-root-b.verity" 6
copy_component "$components/bedrock-root-b.verity-sig.json" 7

work=$(mktemp -d)
cleanup() { rm -f "$work/esp.img" "$work/loader.conf"; rmdir "$work" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

esp_image="$work/esp.img"
truncate -s "$(( $(partition_sectors 1) * 512 ))" "$esp_image"
mformat -i "$esp_image" -F -v BEDROCK_ESP ::
mmd -i "$esp_image" ::/EFI ::/EFI/BOOT ::/EFI/Linux ::/EFI/systemd ::/loader
mcopy -i "$esp_image" "$components/systemd-bootx64.efi" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$esp_image" "$components/systemd-bootx64.efi" ::/EFI/systemd/systemd-bootx64.efi
mcopy -i "$esp_image" "$components/bedrock-a.efi" ::/EFI/Linux/bedrock-a+3.efi
mcopy -i "$esp_image" "$components/bedrock-b.efi" ::/EFI/Linux/bedrock-b+3.efi
printf 'timeout 3\nconsole-mode auto\neditor no\nauto-entries no\nauto-firmware yes\n' > "$work/loader.conf"
mcopy -i "$esp_image" "$work/loader.conf" ::/loader/loader.conf
copy_component "$esp_image" 1

state_start=$(partition_start 8)
state_blocks=$(( $(partition_sectors 8) / 8 ))
mkfs.ext4 -q -F -b 4096 -L bedrock-state -U 30000000-0000-4000-8000-000000000008 \
  -E "offset=$((state_start * 512))" "$output" "$state_blocks"

"$ROOT/os/scripts/verify-disk-image.sh" "$output"
output_dir=$(dirname -- "$output")
output_name=$(basename -- "$output")
(cd "$output_dir" && sha256sum "$output_name" > "$output_name.sha256")
printf 'Assembled verified Bedrock disk image: %s\n' "$output"
