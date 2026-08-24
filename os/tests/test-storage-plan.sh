#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
planner="$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-storage-plan"
inventory="$ROOT/os/tests/storage-plan-inventory.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

make_request() {
  name=$1 backend=$2 layout=$3 ids=$4 confirmation=$5 ack=$6
  jq -n --arg name "$name" --arg backend "$backend" --arg layout "$layout" \
    --arg confirmation "$confirmation" --argjson ids "$ids" --argjson ack "$ack" \
    '{schema:1,name:$name,backend:$backend,layout:$layout,disk_ids:$ids,confirmation:$confirmation,advanced_hardware_raid_ack:$ack}'
}
run_plan() {
  BEDROCK_STORAGE_PLAN_TEST_MODE=1 BEDROCK_STORAGE_PLAN_TEST_NOW=1787602100 \
    "$planner" "$inventory" "$1"
}

make_request vault zfs mirror '["disk-a","disk-b"]' \
  'REVIEW ERASE — vault — zfs mirror — /dev/sdb, /dev/sdc' false > "$work/mirror.json"
run_plan "$work/mirror.json" > "$work/mirror-plan.json"
jq -e '
  .schema == 1 and .operation == "review-storage-creation" and .backend == "zfs" and .layout == "mirror" and
  .disk_count == 2 and .capacity.estimated_usable_bytes == 1000000000000 and
  .resilience.minimum_tolerated_failures == 1 and .destructive == true and .preserve_existing_data == false and
  .review_only == true and .execution_material_present == false and .ready_for_execution == false and
  (.blocked_reason | contains("No storage command")) and (has("commands") | not)
' "$work/mirror-plan.json" >/dev/null

make_request archive zfs raidz2 '["disk-a","disk-b","disk-c","disk-d"]' \
  'REVIEW ERASE — archive — zfs raidz2 — /dev/sdb, /dev/sdc, /dev/sdd, /dev/sde' false > "$work/raidz2.json"
run_plan "$work/raidz2.json" | jq -e '
  .capacity.estimated_usable_bytes == 2000000000000 and
  .capacity.unused_due_to_size_difference_bytes == 400000000000 and
  .resilience.minimum_tolerated_failures == 2 and (.warnings | length) == 2
' >/dev/null

make_request fast mdraid raid10 '["disk-a","disk-b","disk-c","disk-d"]' \
  'REVIEW ERASE — fast — mdraid raid10 — /dev/sdb, /dev/sdc, /dev/sdd, /dev/sde' false > "$work/raid10.json"
run_plan "$work/raid10.json" | jq -e '
  .capacity.estimated_usable_bytes == 2000000000000 and
  .resilience.minimum_tolerated_failures == 1 and (.warnings | length) == 3
' >/dev/null

reject() {
  label=$1 request_file=$2
  if run_plan "$request_file" >/dev/null 2>&1; then
    printf 'error: storage planner accepted %s\n' "$label" >&2
    exit 1
  fi
}
make_request duplicate mdraid raid1 '["disk-a","disk-a"]' x false > "$work/duplicate.json"
reject duplicate-disks "$work/duplicate.json"
make_request too_few zfs raidz2 '["disk-a","disk-b"]' x false > "$work/too-few.json"
reject insufficient-raidz2-members "$work/too-few.json"
make_request odd mdraid raid10 '["disk-a","disk-b","disk-c"]' x false > "$work/odd.json"
reject odd-raid10-members "$work/odd.json"
make_request unsafe zfs mirror '["disk-a","system"]' \
  'REVIEW ERASE — unsafe — zfs mirror — /dev/sdb, /dev/nvme0n1' false > "$work/system.json"
reject system-disk "$work/system.json"
make_request bad zfs mirror '["disk-a","failing"]' \
  'REVIEW ERASE — bad — zfs mirror — /dev/sdb, /dev/sdf' false > "$work/failing.json"
reject failing-disk "$work/failing.json"
make_request sectors zfs mirror '["disk-a","sector-4k"]' \
  'REVIEW ERASE — sectors — zfs mirror — /dev/sdb, /dev/sdg' false > "$work/sectors.json"
reject mixed-sector-sizes "$work/sectors.json"
make_request typo zfs mirror '["disk-a","disk-b"]' 'REVIEW ERASE — something else' false > "$work/confirmation.json"
reject incorrect-confirmation "$work/confirmation.json"
make_request hardware zfs mirror '["raid-a","raid-b"]' \
  'REVIEW ERASE — hardware — zfs mirror — /dev/sdh, /dev/sdi' false > "$work/hardware-no-ack.json"
reject unacknowledged-hardware-raid "$work/hardware-no-ack.json"
make_request hardware zfs mirror '["raid-a","raid-b"]' \
  'REVIEW ERASE — hardware — zfs mirror — /dev/sdh, /dev/sdi' true > "$work/hardware.json"
run_plan "$work/hardware.json" | jq -e '
  .hardware_raid_logical == true and .review_only == true and .ready_for_execution == false and
  (.warnings[] | contains("hides physical-member"))
' >/dev/null
jq '(.disks[] | select(.hardware_raid_logical == true) | .health) = "healthy"' \
  "$inventory" > "$work/dishonest-hardware-inventory.json"
if BEDROCK_STORAGE_PLAN_TEST_MODE=1 "$planner" "$work/dishonest-hardware-inventory.json" "$work/hardware.json" >/dev/null 2>&1; then
  printf 'error: storage planner accepted unverified hardware RAID health as healthy\n' >&2
  exit 1
fi
make_request stacked mdraid raid1 '["raid-a","raid-b"]' \
  'REVIEW ERASE — stacked — mdraid raid1 — /dev/sdh, /dev/sdi' true > "$work/stacked.json"
reject stacked-software-hardware-raid "$work/stacked.json"

jq '.disks[0].size_bytes = 9007199254740992' "$inventory" > "$work/oversized-inventory.json"
if BEDROCK_STORAGE_PLAN_TEST_MODE=1 "$planner" "$work/oversized-inventory.json" "$work/mirror.json" >/dev/null 2>&1; then
  printf 'error: storage planner accepted an unsafe numeric disk size\n' >&2
  exit 1
fi

ln -s "$work/mirror.json" "$work/indirect.json"
reject symbolic-link-request "$work/indirect.json"

printf 'Bedrock review-only ZFS and Linux RAID storage planning tests passed.\n'
