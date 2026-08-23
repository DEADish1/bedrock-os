#!/bin/sh
set -eu

[ "$#" -eq 6 ] || {
  printf 'usage: %s RELEASE_DIR TRUSTED_CERT IMAGE_NAME INVENTORY.json TARGET_ID CONFIRMATION\n' "$0" >&2
  exit 2
}
release=$1
cert=$2
image_name=$3
inventory=$4
target_id=$5
confirmation=$6
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

for tool in jq dd; do command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 2; }; done
sh "$ROOT/installer/core/verify-signed-image.sh" "$release" "$cert" "$image_name" >/dev/null
target=$(sh "$ROOT/installer/core/validate-target-selection.sh" "$inventory" "$target_id" "$confirmation")
path=$(printf '%s\n' "$target" | jq -r .path)
capacity=$(printf '%s\n' "$target" | jq -r .size_bytes)
image="$release/$image_name"
write_size=$(jq -r .artifact.write_size "$release/manifest.json")
[ "$capacity" -ge "$write_size" ] || { printf 'error: selected target is too small for this image\n' >&2; exit 1; }
image_type=$(jq -r .artifact.type "$release/manifest.json")

if [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ]; then
  : "${BEDROCK_TEST_TARGET_DIR:?test mode requires BEDROCK_TEST_TARGET_DIR}"
  test_root=$(CDPATH= cd -- "$BEDROCK_TEST_TARGET_DIR" && pwd)
  target_parent=$(CDPATH= cd -- "$(dirname -- "$path")" && pwd)
  [ "$target_parent" = "$test_root" ] && [ -f "$path" ] ||
    { printf 'error: test target must be a regular file directly inside BEDROCK_TEST_TARGET_DIR\n' >&2; exit 1; }
else
  [ "$(id -u)" -eq 0 ] || { printf 'error: media writing requires administrator privileges\n' >&2; exit 1; }
  [ -b "$path" ] || { printf 'error: validated target is no longer a whole block device\n' >&2; exit 1; }
fi

printf 'Writing verified Bedrock image to %s...\n' "$path"
case "$image_type" in
  iso)
    dd if="$image" of="$path" bs=1048576 conv=fsync,notrunc 2>/dev/null || write_failed=1
    ;;
  raw-zst)
    command -v zstd >/dev/null 2>&1 || { printf 'error: zstd is required to write this raw image\n' >&2; exit 1; }
    zstd -dc "$image" | dd of="$path" bs=1048576 conv=fsync,notrunc 2>/dev/null || write_failed=1
    ;;
  *) write_failed=1 ;;
esac
[ "${write_failed:-0}" = 0 ] || {
  printf 'error: media write was interrupted or incomplete; reconnect or replace the drive and rewrite it from the beginning\n' >&2
  exit 1
}
sync
[ "${BEDROCK_TEST_INTERRUPT_AFTER_WRITE:-0}" != 1 ] || {
  printf 'error: media write was interrupted; the drive is incomplete and must be rewritten from the beginning\n' >&2
  exit 1
}

expected_hash=$(jq -r .artifact.write_sha256 "$release/manifest.json")
if command -v sha256sum >/dev/null 2>&1; then
  actual_hash=$(dd if="$path" bs=1048576 count=$(( (write_size + 1048575) / 1048576 )) 2>/dev/null | head -c "$write_size" | sha256sum | awk '{print $1}')
else
  actual_hash=$(dd if="$path" bs=1048576 count=$(( (write_size + 1048575) / 1048576 )) 2>/dev/null | head -c "$write_size" | shasum -a 256 | awk '{print $1}')
fi
[ "$actual_hash" = "$expected_hash" ] || {
  printf 'error: written media failed verification; do not boot it, and retry with another drive\n' >&2
  exit 1
}

printf 'Bedrock media written and verified: %s\n' "$path"
