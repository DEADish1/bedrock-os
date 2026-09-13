#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
collector="$ROOT/os/config/includes.chroot/usr/lib/bedrock/collect-storage-health"
fixture="$ROOT/os/tests/fixtures/storage"
service="$ROOT/os/config/includes.chroot/usr/lib/systemd/system/bedrock-storage-health.service"
timer="$ROOT/os/config/includes.chroot/usr/lib/systemd/system/bedrock-storage-health.timer"
timer_link="$ROOT/os/config/includes.chroot/etc/systemd/system/timers.target.wants/bedrock-storage-health.timer"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
printf '%s\n' '{"schema":1,"pools":[{"name":"archive","backend":"mdraid","layout":"raid6","devices":["/dev/private"],"state":"exported"},{"name":"vault","backend":"zfs","layout":"mirror","devices":["/dev/sdc"],"state":"online"}]}' > "$work/resources.json"

BEDROCK_STORAGE_TEST_MODE=1 BEDROCK_STORAGE_PROC_ROOT="$fixture/proc" \
BEDROCK_STORAGE_TEST_PATH="$fixture/bin${BEDROCK_TEST_EXTRA_PATH:+:$BEDROCK_TEST_EXTRA_PATH}" BEDROCK_STORAGE_TEST_NOW=1787601000 \
BEDROCK_STORAGE_TEST_RESOURCES="$work/resources.json" \
BEDROCK_STORAGE_TEST_CANDIDATES="$work/candidates.json" \
  "$collector" "$work/health.json"

jq -e '
  .schema == 1 and .generated_unix == 1787601000 and .read_only == true and .overall == "attention" and
  (.disks | length == 4) and
  (.disk_candidates | length == 4) and
  (.disk_candidates[0] | (.id|test("^disk-[0-9a-f]{20}$")) and .eligible == false and .reason == "system" and has("path") == false) and
  (.disk_candidates[1] | (.id|test("^disk-[0-9a-f]{20}$")) and .eligible == false and .reason == "failing" and has("path") == false) and
  (.disk_candidates[2] | .eligible == false and .reason == "managed") and
  (.disk_candidates[3] | .eligible == true and .reason == "available") and
  .disks[0].smart.health == "healthy" and .disks[0].smart.temperature_c == 31 and
  .disks[1].smart.health == "failing" and .disks[1].smart.command_exit == 8 and
  (.managed_pools[0] | .name=="archive" and .members==[]) and
  (.managed_pools[1] | .name=="vault" and (.members|length)==1 and (.members[0]|test("^disk-[0-9a-f]{20}$"))) and
  (.software_raid.md_arrays | length == 2) and
  .software_raid.md_arrays[0].health == "healthy" and
  .software_raid.md_arrays[1].health == "degraded" and
  .software_raid.md_arrays[1].active_members == 2 and
  .software_raid.md_arrays[1].sync.action == "recovery" and
  .software_raid.md_arrays[1].sync.percent == 23.4 and
  .software_raid.zfs.available == true and (.software_raid.zfs.pools | length == 2) and
  .software_raid.zfs.pools[1].status == "degraded" and
  (.hardware_raid.controllers | length == 1) and
  .hardware_raid.controllers[0].health_visibility == "limited" and
  .hardware_raid.controllers[0].member_health_available == false and
  (.hardware_raid.vendor_reports | length) == 1 and
  .hardware_raid.vendor_reports[0].physical_drives[1].state == "Rbld" and
  .hardware_raid.vendor_reports[0].physical_drives[1].rebuild_percent == 42 and
  .hardware_raid.vendor_reports[0].logical_volumes[0].healthy == false and
  .hardware_raid.vendor_reports[0].cache_protection[0].healthy == true
' "$work/health.json" >/dev/null
case $(uname -s) in
  MINGW*) : ;;
  *)
    jq -e '.schema==1 and .generated_unix==1787601000 and (.disks|length)==4 and .disks[0].path=="/dev/sda" and .disks[3].path=="/dev/sdd"' "$work/candidates.json" >/dev/null
    [ "$(stat -c %a "$work/candidates.json")" = 600 ]
    ;;
esac
BEDROCK_STORAGE_TEST_MODE=1 BEDROCK_STORAGE_PROC_ROOT="$fixture/proc" \
BEDROCK_STORAGE_TEST_PATH="$fixture/bin${BEDROCK_TEST_EXTRA_PATH:+:$BEDROCK_TEST_EXTRA_PATH}" BEDROCK_STORAGE_TEST_NOW=1787601001 \
BEDROCK_STORAGE_TEST_RESOURCES="$work/resources.json" BEDROCK_STORAGE_TEST_CANDIDATES="$work/candidates-repeat.json" \
  "$collector" "$work/health-repeat.json"
jq -e --slurpfile first "$work/health.json" '[.disk_candidates[].id]==[$first[0].disk_candidates[].id]' "$work/health-repeat.json" >/dev/null

ln -s "$work/elsewhere.json" "$work/indirect.json"
if BEDROCK_STORAGE_TEST_MODE=1 BEDROCK_STORAGE_PROC_ROOT="$fixture/proc" \
  BEDROCK_STORAGE_TEST_PATH="$fixture/bin${BEDROCK_TEST_EXTRA_PATH:+:$BEDROCK_TEST_EXTRA_PATH}" "$collector" "$work/indirect.json" >/dev/null 2>&1; then
  printf 'error: storage health collector accepted a symbolic-link output\n' >&2
  exit 1
fi

if BEDROCK_STORAGE_TEST_MODE=1 BEDROCK_STORAGE_UNSAFE_FIXTURE=1 \
  BEDROCK_STORAGE_PROC_ROOT="$fixture/proc" BEDROCK_STORAGE_TEST_PATH="$fixture/bin${BEDROCK_TEST_EXTRA_PATH:+:$BEDROCK_TEST_EXTRA_PATH}" \
  "$collector" "$work/unsafe.json" >/dev/null 2>&1; then
  printf 'error: storage health collector accepted an unsafe disk path\n' >&2
  exit 1
fi

grep -q '^ExecStart=/usr/lib/bedrock/collect-storage-health$' "$service"
grep -q '^RestrictAddressFamilies=AF_UNIX$' "$service"
grep -q '^OnUnitActiveSec=10min$' "$timer"
[ -L "$timer_link" ] &&
  [ "$(readlink "$timer_link")" = '../../../../usr/lib/systemd/system/bedrock-storage-health.timer' ] || {
  printf 'error: storage health timer enablement is invalid\n' >&2
  exit 1
}

printf 'Bedrock read-only disk, SMART, software RAID, ZFS, and hardware RAID health tests passed.\n'
