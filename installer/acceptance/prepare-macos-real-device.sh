#!/bin/sh
set -eu

[ "$#" -eq 3 ] || {
  printf 'usage: %s TARGET_ID CONFIRMATION PLAN.json\n' "$0" >&2
  exit 2
}
target_id=$1
confirmation=$2
plan=$3
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

[ "${BEDROCK_REAL_DEVICE_ACCEPTANCE:-}" = "I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE" ] || {
  printf 'error: macOS acceptance requires the exact destructive opt-in sentence\n' >&2
  exit 1
}
: "${BEDROCK_ACCEPTANCE_TARGET_PATH:?set the displayed whole-disk path}"
: "${BEDROCK_ACCEPTANCE_TARGET_SIZE:?set the displayed capacity in bytes}"

fixture=${BEDROCK_ACCEPTANCE_FIXTURE_MODE:-0}
if [ "$fixture" = 1 ]; then
  : "${BEDROCK_MACOS_DISKS_JSON:?fixture mode requires BEDROCK_MACOS_DISKS_JSON}"
  mode=fixture
else
  [ "$(uname -s)" = Darwin ] || { printf 'error: this preflight requires macOS\n' >&2; exit 1; }
  [ "$(id -u)" -eq 0 ] || { printf 'error: physical acceptance requires root authority\n' >&2; exit 1; }
  mode=physical
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
inventory="$work/fresh-inventory.json"
sh "$ROOT/installer/adapters/macos-list-targets.sh" > "$inventory"
target=$(sh "$ROOT/installer/core/validate-target-selection.sh" \
  "$inventory" "$target_id" "$confirmation")
path=$(printf '%s\n' "$target" | jq -r .path)
model=$(printf '%s\n' "$target" | jq -r .model)
size=$(printf '%s\n' "$target" | jq -r .size_bytes)
[ "$path" = "$BEDROCK_ACCEPTANCE_TARGET_PATH" ] && \
[ "$size" = "$BEDROCK_ACCEPTANCE_TARGET_SIZE" ] || {
  printf 'error: fresh macOS identity does not match the path/capacity attestation\n' >&2
  exit 1
}
printf '%s\n' "$path" | grep -Eq '^/dev/disk[0-9]+$' || {
  printf 'error: macOS target is not an exact whole-disk path\n' >&2
  exit 1
}
maximum_default=$((256 * 1024 * 1024 * 1024))
if [ "$size" -gt "$maximum_default" ] && \
   [ "${BEDROCK_ACCEPTANCE_LARGE_DRIVE:-}" != "I CONFIRM THIS LARGE DRIVE IS DISPOSABLE" ]; then
  printf 'error: drives over 256 GiB require the additional large-drive attestation\n' >&2
  exit 1
fi

mkdir -p "$(dirname -- "$plan")"
jq -n --arg mode "$mode" --arg id "$target_id" --arg path "$path" \
  --arg model "$model" --argjson size "$size" '{
    schema:1,mode:$mode,platform:"macos",ready_for_writer:false,
    target:{id:$id,path:$path,model:$model,size_bytes:$size,disposable:true},
    checks:{fresh_inventory:true,exact_confirmation:true,whole_device:true,
      removable:true,unmounted:true,writable:true}
  }' > "$plan"
printf 'macOS disposable-drive preflight passed; physical writing remains disabled: %s\n' "$plan"
