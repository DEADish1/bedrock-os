#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
processor="$ROOT/os/config/includes.chroot/usr/lib/bedrock/process-storage-alerts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

jq -n '{
  schema:1,generated_unix:100,overall:"attention",read_only:true,
  disks:[
    {path:"/dev/sda",smart:{health:"healthy",temperature_c:31}},
    {path:"/dev/sdb",smart:{health:"failing",temperature_c:66}}
  ],
  software_raid:{md_arrays:[{name:"md0",path:"/dev/md0",health:"degraded",active_members:1,expected_members:2}],
    zfs:{available:true,pools:[{name:"archive",health:"DEGRADED",status:"degraded"}]}},
  hardware_raid:{controllers:[{address:"0000:03:00.0",member_health_available:false}],vendor_reports:[]}
}' > "$work/health.json"

BEDROCK_STORAGE_ALERT_TEST_MODE=1 BEDROCK_STORAGE_ALERT_TEST_NOW=1000 \
  "$processor" "$work/health.json" "$work/alerts.json"
jq -e '
  .schema == 1 and .source_generated_unix == 100 and .attention_required == true and
  .active_count == 5 and (.events | length == 5) and all(.events[]; .action == "opened") and
  ([.active[].kind] | sort) == (["disk-smart","disk-temperature","hardware-raid-visibility","md-degraded","zfs-health"] | sort) and
  (.active[] | select(.kind == "disk-temperature") | .severity) == "critical" and
  all(.active[]; .first_seen_unix == 1000 and .last_seen_unix == 1000)
' "$work/alerts.json" >/dev/null

jq '.hardware_raid.vendor_reports=[{tool:"storcli64",controller:0,status:"Degraded",healthy:false,
  physical_drives:[{slot:"252:1",state:"Rbld",healthy:false}],
  logical_volumes:[{id:"0/0",state:"Dgrd",healthy:false}],
  cache_protection:[{model:"CVPM05",state:"Failed",healthy:false}]}]' "$work/health.json" > "$work/vendor-health.json"
BEDROCK_STORAGE_ALERT_TEST_MODE=1 BEDROCK_STORAGE_ALERT_TEST_NOW=1000 \
  "$processor" "$work/vendor-health.json" "$work/vendor-alerts.json"
jq -e '
  .active_count == 8 and
  ([.active[].kind] | index("hardware-raid-visibility") | not) and
  ([.active[].kind] | contains(["hardware-raid-cache","hardware-raid-controller","hardware-raid-disk","hardware-raid-volume"]))
' "$work/vendor-alerts.json" >/dev/null

BEDROCK_STORAGE_ALERT_TEST_MODE=1 BEDROCK_STORAGE_ALERT_TEST_NOW=1010 \
  "$processor" "$work/health.json" "$work/alerts.json"
jq -e '
  .active_count == 5 and (.events | length == 5) and
  all(.active[]; .first_seen_unix == 1000 and .last_seen_unix == 1010)
' "$work/alerts.json" >/dev/null

BEDROCK_STORAGE_ALERT_TEST_MODE=1 BEDROCK_STORAGE_ALERT_TEST_NOW=900 \
  "$processor" "$work/health.json" "$work/alerts.json"
jq -e '
  .generated_unix == 1010 and (.events | length == 5) and
  all(.active[]; .first_seen_unix == 1000 and .last_seen_unix == 1010)
' "$work/alerts.json" >/dev/null

jq '.generated_unix = 105 | .disks[1].smart.temperature_c = 58' \
  "$work/health.json" > "$work/warm.json"
BEDROCK_STORAGE_ALERT_TEST_MODE=1 BEDROCK_STORAGE_ALERT_TEST_NOW=1015 \
  "$processor" "$work/warm.json" "$work/alerts.json"
jq -e '
  .active_count == 5 and (.events | length == 6) and
  .events[-1].action == "severity-changed" and .events[-1].previous_severity == "critical" and
  .events[-1].severity == "warning" and
  (.active[] | select(.kind == "disk-temperature") | .first_seen_unix) == 1000
' "$work/alerts.json" >/dev/null

jq '
  .generated_unix = 110 |
  .disks[1].smart = {health:"healthy",temperature_c:40} |
  .software_raid.md_arrays = [] |
  .software_raid.zfs.pools = [] |
  .hardware_raid.controllers = []
' "$work/health.json" > "$work/healthy.json"
BEDROCK_STORAGE_ALERT_TEST_MODE=1 BEDROCK_STORAGE_ALERT_TEST_NOW=1020 \
  "$processor" "$work/healthy.json" "$work/alerts.json"
jq -e '
  .source_generated_unix == 110 and .attention_required == false and .active_count == 0 and
  (.events | length == 11) and ([.events[-5:][] | .action] | unique) == ["resolved"]
' "$work/alerts.json" >/dev/null

ln -s "$work/elsewhere.json" "$work/indirect.json"
if BEDROCK_STORAGE_ALERT_TEST_MODE=1 "$processor" "$work/health.json" "$work/indirect.json" >/dev/null 2>&1; then
  printf 'error: storage alert processor accepted a symbolic-link output\n' >&2
  exit 1
fi
jq '.read_only = false' "$work/health.json" > "$work/invalid-health.json"
if BEDROCK_STORAGE_ALERT_TEST_MODE=1 "$processor" "$work/invalid-health.json" "$work/invalid-alerts.json" >/dev/null 2>&1; then
  printf 'error: storage alert processor accepted mutable health input\n' >&2
  exit 1
fi
jq '.disks[0].smart.temperature_c = "hot"' "$work/health.json" > "$work/invalid-temperature.json"
if BEDROCK_STORAGE_ALERT_TEST_MODE=1 "$processor" "$work/invalid-temperature.json" "$work/invalid-alerts.json" >/dev/null 2>&1; then
  printf 'error: storage alert processor accepted a malformed temperature\n' >&2
  exit 1
fi
jq '.disks[0].path = "/dev/.."' "$work/health.json" > "$work/unsafe-path.json"
if BEDROCK_STORAGE_ALERT_TEST_MODE=1 "$processor" "$work/unsafe-path.json" "$work/invalid-alerts.json" >/dev/null 2>&1; then
  printf 'error: storage alert processor accepted an unsafe disk path\n' >&2
  exit 1
fi
jq '.events[0].event_id = .events[1].event_id' "$work/alerts.json" > "$work/duplicate-history.json"
if BEDROCK_STORAGE_ALERT_TEST_MODE=1 "$processor" "$work/healthy.json" "$work/duplicate-history.json" >/dev/null 2>&1; then
  printf 'error: storage alert processor accepted duplicate audit event IDs\n' >&2
  exit 1
fi
jq -n '{schema:1,generated_unix:1,source_generated_unix:1,attention_required:false,active_count:0,active:[],
  events:[range(0;1000) | {event_id:("old:" + tostring),action:"resolved",alert_id:("old:" + tostring),
    kind:"test",resource:"test",severity:"warning",previous_severity:"warning",occurred_unix:.}]}' \
  > "$work/bounded-alerts.json"
BEDROCK_STORAGE_ALERT_TEST_MODE=1 BEDROCK_STORAGE_ALERT_TEST_NOW=2000 \
  "$processor" "$work/health.json" "$work/bounded-alerts.json"
jq -e '
  (.events | length) == 1000 and ([.events[-5:][] | .action] | unique) == ["opened"]
' "$work/bounded-alerts.json" >/dev/null

grep -q '^ExecStart=/usr/lib/bedrock/process-storage-alerts$' \
  "$ROOT/os/config/includes.chroot/usr/lib/systemd/system/bedrock-storage-health.service"

printf 'Bedrock deduplicated storage alert and audit-history tests passed.\n'
