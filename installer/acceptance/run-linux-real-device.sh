#!/bin/sh
set -eu

[ "$#" -eq 6 ] || {
  printf 'usage: %s RELEASE_DIR TRUSTED_CERT IMAGE_NAME TARGET_ID CONFIRMATION REPORT.json\n' "$0" >&2
  exit 2
}
release=$1
cert=$2
image_name=$3
target_id=$4
confirmation=$5
report=$6
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

[ "${BEDROCK_REAL_DEVICE_ACCEPTANCE:-}" = "I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE" ] || {
  printf 'error: real-device acceptance requires the exact destructive opt-in sentence\n' >&2
  exit 1
}
: "${BEDROCK_ACCEPTANCE_TARGET_PATH:?set BEDROCK_ACCEPTANCE_TARGET_PATH to the displayed whole-device path}"
: "${BEDROCK_ACCEPTANCE_TARGET_SIZE:?set BEDROCK_ACCEPTANCE_TARGET_SIZE to the displayed capacity in bytes}"

fixture=${BEDROCK_ACCEPTANCE_FIXTURE_MODE:-0}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
inventory="$work/fresh-inventory.json"
if [ "$fixture" = 1 ]; then
  : "${BEDROCK_ACCEPTANCE_FIXTURE_INVENTORY:?fixture mode requires a fixture inventory}"
  : "${BEDROCK_ACCEPTANCE_FIXTURE_TARGET_DIR:?fixture mode requires a fixture target directory}"
  cp "$BEDROCK_ACCEPTANCE_FIXTURE_INVENTORY" "$inventory"
  report_mode=fixture
else
  [ "$(uname -s)" = Linux ] || { printf 'error: this acceptance runner supports Linux only\n' >&2; exit 1; }
  [ "$(id -u)" -eq 0 ] || { printf 'error: physical acceptance requires root authority\n' >&2; exit 1; }
  sh "$ROOT/installer/adapters/linux-list-targets.sh" > "$inventory"
  report_mode=physical
fi

target=$(sh "$ROOT/installer/core/validate-target-selection.sh" \
  "$inventory" "$target_id" "$confirmation")
path=$(printf '%s\n' "$target" | jq -r .path)
model=$(printf '%s\n' "$target" | jq -r .model)
size=$(printf '%s\n' "$target" | jq -r .size_bytes)
[ "$path" = "$BEDROCK_ACCEPTANCE_TARGET_PATH" ] || {
  printf 'error: the freshly scanned path does not match the operator attestation\n' >&2
  exit 1
}
[ "$size" = "$BEDROCK_ACCEPTANCE_TARGET_SIZE" ] || {
  printf 'error: the freshly scanned capacity does not match the operator attestation\n' >&2
  exit 1
}

maximum_default=$((256 * 1024 * 1024 * 1024))
if [ "$size" -gt "$maximum_default" ] && \
   [ "${BEDROCK_ACCEPTANCE_LARGE_DRIVE:-}" != "I CONFIRM THIS LARGE DRIVE IS DISPOSABLE" ]; then
  printf 'error: drives over 256 GiB require the additional large-drive attestation\n' >&2
  exit 1
fi

if [ "$fixture" = 1 ]; then
  BEDROCK_INSTALLER_TEST_MODE=1 \
  BEDROCK_TEST_TARGET_DIR="$BEDROCK_ACCEPTANCE_FIXTURE_TARGET_DIR" \
    sh "$ROOT/installer/core/write-verified-image.sh" \
      "$release" "$cert" "$image_name" "$inventory" "$target_id" "$confirmation" >/dev/null
else
  case "$path" in /dev/*) ;; *) printf 'error: target is not a direct Linux device path\n' >&2; exit 1;; esac
  [ "$(dirname -- "$path")" = /dev ] && [ -b "$path" ] || {
    printf 'error: target is not a direct whole block device\n' >&2
    exit 1
  }
  name=$(basename -- "$path")
  sysfs="/sys/class/block/$name"
  [ -d "$sysfs" ] && [ ! -e "$sysfs/partition" ] && [ "$(cat "$sysfs/removable")" = 1 ] || {
    printf 'error: kernel identity does not confirm a removable whole device\n' >&2
    exit 1
  }
  sh "$ROOT/installer/core/write-verified-image.sh" \
    "$release" "$cert" "$image_name" "$inventory" "$target_id" "$confirmation" >/dev/null
fi

image_sha256=$(jq -r .artifact.write_sha256 "$release/manifest.json")
completed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
mkdir -p "$(dirname -- "$report")"
jq -n \
  --arg mode "$report_mode" \
  --arg completed_at "$completed_at" \
  --arg image_sha256 "$image_sha256" \
  --arg target_id "$target_id" \
  --arg path "$path" \
  --arg model "$model" \
  --argjson size_bytes "$size" \
  '{
    schema:2, mode:$mode, platform:"linux", completed_at:$completed_at,
    boot_completed_at:null,
    image_sha256:$image_sha256,
    target:{id:$target_id,path:$path,model:$model,size_bytes:$size_bytes,disposable:true},
    checks:{fresh_inventory:true,exact_confirmation:true,write_completed:true,
      reread_checksum:true,cache_synchronized:true,manual_removal_safe:true,
      booted_from_media:false,guided_installer_opened:false}
  }' > "$report"
printf 'Bedrock disposable-drive write report created; physical boot observations are still required: %s\n' "$report"
