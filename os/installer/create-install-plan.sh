#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
[ "$#" -eq 3 ] || {
  printf 'usage: %s INVENTORY.json TARGET_ID CONFIRMATION\n' "$0" >&2
  exit 2
}

inventory=$1
target_id=$2
confirmation=$3
layout="$ROOT/os/layout/bedrock-amd64.json"
validator="$ROOT/os/installer/validate-install-target.sh"

for tool in jq sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 2; }
done

target=$(sh "$validator" "$inventory" "$target_id" "$confirmation" "$layout")
layout_sha256=$(sha256sum "$layout" | awk '{print $1}')
generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

jq -n -c \
  --arg generated_at "$generated_at" \
  --arg layout_sha256 "$layout_sha256" \
  --arg confirmation "$confirmation" \
  --argjson target "$target" \
  --slurpfile layout "$layout" '
  {
    schema: 1,
    operation: "install-bedrock-system",
    generated_at: $generated_at,
    source: "packaged-signed-live-system",
    target: $target,
    confirmation: $confirmation,
    layout: {
      schema: $layout[0].schema,
      sha256: $layout_sha256,
      architecture: $layout[0].architecture,
      firmware: $layout[0].firmware,
      minimum_disk_bytes: $layout[0].minimum_disk_bytes,
      partitions: ($layout[0].partitions | map({number, name, role, type_guid, filesystem, size_bytes, minimum_size_bytes, grow, mutable}))
    },
    preserve_existing_data: false,
    requires_fresh_inventory: true,
    requires_exclusive_whole_disk: true,
    ready_for_writer: false,
    blocked_reason: "The privileged on-server writer is not connected. This is a review-only plan."
  }
'
