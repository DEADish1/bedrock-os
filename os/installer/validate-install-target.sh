#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$SCRIPT_DIR" = /usr/lib/bedrock/installer ]; then
  default_layout=/usr/share/bedrock/installer/bedrock-amd64.json
else
  ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
  default_layout="$ROOT/os/layout/bedrock-amd64.json"
fi
inventory=${1:-}
target_id=${2:-}
confirmation=${3:-}
layout=${4:-$default_layout}

[ -f "$inventory" ] && [ -f "$layout" ] && [ -n "$target_id" ] || {
  printf 'usage: %s INVENTORY.json TARGET_ID CONFIRMATION [LAYOUT.json]\n' "$0" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }

minimum=$(jq -er '
  select(
    .schema == 1 and .architecture == "amd64" and .firmware == "uefi" and
    (.minimum_disk_bytes | type == "number" and floor == . and . > 0) and
    (.partitions | type == "array" and length == 8)
  ) | .minimum_disk_bytes
' "$layout") || { printf 'error: invalid Bedrock system-disk layout\n' >&2; exit 1; }

jq -e '
  .schema == 1 and (.generated_at | type == "string" and length > 0) and
  (.targets | type == "array")
' "$inventory" >/dev/null || { printf 'error: invalid installation-target inventory\n' >&2; exit 1; }

count=$(jq --arg id "$target_id" '[.targets[] | select(.id == $id)] | length' "$inventory")
[ "$count" -eq 1 ] || { printf 'error: installation target identity is missing or ambiguous\n' >&2; exit 1; }

target=$(jq -c --arg id "$target_id" '.targets[] | select(.id == $id)' "$inventory")
printf '%s\n' "$target" | jq -e --argjson minimum "$minimum" '
  (.id | type == "string" and length > 0 and length <= 512) and
  (.path | type == "string" and test("^/dev/[A-Za-z0-9._-]+$") and length <= 128) and
  (.model | type == "string" and length > 0 and length <= 256 and (contains("\n") | not)) and
  (.size_bytes | type == "number" and floor == . and . >= $minimum) and
  .removable == false and .system == false and .mounted == false and .read_only == false
' >/dev/null || { printf 'error: selected disk is not an eligible Bedrock system target\n' >&2; exit 1; }

expected=$(printf '%s\n' "$target" | jq -r '"INSTALL BEDROCK — \(.model) — \(.path) — \(.size_bytes)"')
[ "$confirmation" = "$expected" ] || {
  printf 'error: confirmation does not exactly name the selected system disk\n' >&2
  exit 1
}

printf '%s\n' "$target"
