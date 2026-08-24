#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$ROOT/os/tests/install-targets.json"
validator="$ROOT/os/installer/validate-install-target.sh"
planner="$ROOT/os/installer/create-install-plan.sh"
layout="$ROOT/os/layout/bedrock-amd64.json"
adapter="$ROOT/installer/adapters/linux-list-targets.sh"
lsblk_fixture="$ROOT/installer/tests/linux-lsblk.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

confirmation='INSTALL BEDROCK — Test System SSD — /dev/nvme1n1 — 68719476736'
sh "$validator" "$fixture" linux:install-safe "$confirmation" | jq -e '
  .id == "linux:install-safe" and .path == "/dev/nvme1n1" and .system == false
' >/dev/null

sh "$planner" "$fixture" linux:install-safe "$confirmation" > "$work/plan.json"
layout_sha256=$(sha256sum "$layout" | awk '{print $1}')
jq -e --arg hash "$layout_sha256" '
  .schema == 1 and .operation == "install-bedrock-system" and
  .source == "packaged-signed-live-system" and
  .target.id == "linux:install-safe" and
  .layout.sha256 == $hash and .layout.minimum_disk_bytes == 34359738368 and
  (.layout.partitions | length == 8) and
  .preserve_existing_data == false and
  .requires_fresh_inventory == true and
  .requires_exclusive_whole_disk == true and
  .ready_for_writer == false and
  (.blocked_reason | contains("review-only plan"))
' "$work/plan.json" >/dev/null

for id in \
  linux:live-media linux:running-system linux:mounted-data linux:read-only \
  linux:too-small linux:other-usb linux:missing; do
  if sh "$validator" "$fixture" "$id" "$confirmation" >/dev/null 2>&1; then
    printf 'error: unsafe installation target was accepted: %s\n' "$id" >&2
    exit 1
  fi
done

if sh "$validator" "$fixture" linux:install-safe \
  'INSTALL BEDROCK — a different disk' >/dev/null 2>&1; then
  printf 'error: incomplete installation confirmation was accepted\n' >&2
  exit 1
fi

jq '.targets += [.targets[] | select(.id == "linux:install-safe")]' "$fixture" > "$work/ambiguous.json"
if sh "$validator" "$work/ambiguous.json" linux:install-safe "$confirmation" >/dev/null 2>&1; then
  printf 'error: ambiguous installation identity was accepted\n' >&2
  exit 1
fi

jq '.minimum_disk_bytes = 0' "$layout" > "$work/bad-layout.json"
if sh "$validator" "$fixture" linux:install-safe "$confirmation" "$work/bad-layout.json" >/dev/null 2>&1; then
  printf 'error: invalid system layout was accepted\n' >&2
  exit 1
fi

jq '
  walk(
    if type == "object" and .path? == "/dev/nvme0n1p2" then .mountpoints = [null]
    elif type == "object" and .path? == "/dev/sdb" then .mountpoints = ["/run/live/medium"]
    else . end
  )
' "$lsblk_fixture" > "$work/live-lsblk.json"
BEDROCK_LSBLK_JSON=$(cat "$work/live-lsblk.json") sh "$adapter" > "$work/live-inventory.json"
jq -e '
  ([.targets[] | select(.path == "/dev/sdb" and .system == true)] | length == 1) and
  ([.targets[] | select(.path == "/dev/nvme0n1" and .system == false and .mounted == false)] | length == 1)
' "$work/live-inventory.json" >/dev/null
live_target_id=$(jq -r '.targets[] | select(.path == "/dev/nvme0n1") | .id' "$work/live-inventory.json")
sh "$validator" "$work/live-inventory.json" "$live_target_id" \
  'INSTALL BEDROCK — Internal SSD — /dev/nvme0n1 — 512110190592' >/dev/null

printf 'Bedrock on-server installation plan safety tests passed.\n'
