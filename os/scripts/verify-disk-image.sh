#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$SCRIPT_DIR" = /usr/lib/bedrock/installer ]; then
  LAYOUT=/usr/share/bedrock/installer/bedrock-amd64.json
else
  ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
  LAYOUT="$ROOT/os/layout/bedrock-amd64.json"
fi
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { printf 'usage: %s IMAGE.raw [TEST-LAYOUT.json]\n' "$0" >&2; exit 2; }
image=$1
if [ "$#" -eq 2 ]; then
  [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ] || { printf 'error: alternate layouts are test-only\n' >&2; exit 1; }
  LAYOUT=$2
fi
[ -s "$image" ] || { printf 'error: disk image is missing\n' >&2; exit 1; }
for tool in jq sgdisk; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }
done

[ "$(wc -c < "$image" | tr -d ' ')" -ge "$(jq -r '.minimum_disk_bytes' "$LAYOUT")" ] || { printf 'error: disk image is too small\n' >&2; exit 1; }
sgdisk --verify "$image" >/dev/null

jq -c '.partitions[]' "$LAYOUT" | while IFS= read -r partition; do
  number=$(printf '%s' "$partition" | jq -r '.number')
  expected_name=$(printf '%s' "$partition" | jq -r '.name')
  expected_type=$(printf '%s' "$partition" | jq -r '.type_guid' | tr '[:lower:]' '[:upper:]')
  info=$(sgdisk --info="$number" "$image")
  printf '%s\n' "$info" | grep -F "Partition name: '$expected_name'" >/dev/null || { printf 'error: partition %s label differs\n' "$number" >&2; exit 1; }
  printf '%s\n' "$info" | grep -F "Partition GUID code: $expected_type" >/dev/null || { printf 'error: partition %s type differs\n' "$number" >&2; exit 1; }
done

printf 'Bedrock GPT disk structure is valid.\n'
