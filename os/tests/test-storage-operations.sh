#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-storage"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin"
for command in jq mktemp grep wc tr date dirname mkdir chmod mv rm rmdir; do
  path=$(command -v "$command")
  [ -n "$path" ] && ln -s "$path" "$work/bin/$command"
done
state=$work/state.json audit=$work/audit.jsonl

request() {
  jq -n --arg action "$1" --arg backend "$2" --arg name "$3" --arg pool "$3" --arg layout "$4" \
    --argjson devices "$5" --arg confirmation "$6" \
    '{schema:1,action:$action,backend:$backend,name:$name,pool:$pool,layout:$layout,devices:$devices,confirmation:$confirmation}'
}
run() {
  BEDROCK_STORAGE_OPERATION_TEST_MODE=1 BEDROCK_STORAGE_OPERATION_TEST_PATH="$work/bin" \
  BEDROCK_STORAGE_OPERATION_TEST_NOW="$1" BEDROCK_STORAGE_OPERATION_TEST_AUDIT="$audit" \
    "$tool" "$2" "$3" "$state"
}

request create zfs vault mirror '["/dev/sdb","/dev/sdc"]' \
  'ERASE AND CREATE — vault — zfs mirror — /dev/sdb, /dev/sdc' > "$work/create.json"
run 100 plan "$work/create.json" | jq -e '.ready_for_execution and .destructive and .action == "create"' >/dev/null
run 100 apply "$work/create.json" | jq -e '.result == "completed"' >/dev/null
jq -e '.pools[0].name == "vault" and .pools[0].state == "online" and (.pools[0].devices | length) == 2' "$state" >/dev/null

request expand zfs vault mirror '["/dev/sdd","/dev/sde"]' 'EXPAND — vault — /dev/sdd, /dev/sde' > "$work/expand.json"
run 110 apply "$work/expand.json" >/dev/null
jq -e '(.pools[0].devices | length) == 4' "$state" >/dev/null

request scrub zfs vault none '[]' 'SCRUB — vault' > "$work/scrub.json"
run 120 apply "$work/scrub.json" >/dev/null
jq -e '.pools[0].last_scrub_unix == 120' "$state" >/dev/null

request replace zfs vault none '["/dev/sdb","/dev/sdf"]' 'REPLACE — vault — /dev/sdb, /dev/sdf' > "$work/replace.json"
run 130 apply "$work/replace.json" >/dev/null
jq -e '.pools[0].state == "rebuilding" and (.pools[0].devices | index("/dev/sdb") | not) and (.pools[0].devices | index("/dev/sdf"))' "$state" >/dev/null
run 135 apply "$work/scrub.json" >/dev/null
jq -e '.pools[0].state == "online"' "$state" >/dev/null

request export zfs vault none '[]' 'EXPORT — vault' > "$work/export.json"
run 140 apply "$work/export.json" >/dev/null
jq -e '.pools[0].state == "exported"' "$state" >/dev/null
request import zfs vault none '[]' 'IMPORT — vault' > "$work/import.json"
run 150 apply "$work/import.json" >/dev/null
jq -e '.pools[0].state == "online"' "$state" >/dev/null
[ "$(wc -l < "$audit" | tr -d ' ')" -eq 7 ]

request create mdraid archive raid6 '["/dev/sdg","/dev/sdh","/dev/sdi","/dev/sdj"]' \
  'ERASE AND CREATE — archive — mdraid raid6 — /dev/sdg, /dev/sdh, /dev/sdi, /dev/sdj' > "$work/md.json"
run 160 apply "$work/md.json" >/dev/null
jq -e '.pools[1].backend == "mdraid" and .pools[1].layout == "raid6"' "$state" >/dev/null

request create zfs unsafe mirror '["/dev/sdk","/dev/sdl"]' wrong > "$work/wrong.json"
if run 170 apply "$work/wrong.json" >/dev/null 2>&1; then
  printf 'error: storage operation accepted an incorrect destructive confirmation\n' >&2; exit 1
fi
request create mdraid odd raid10 '["/dev/sdm","/dev/sdn","/dev/sdo"]' \
  'ERASE AND CREATE — odd — mdraid raid10 — /dev/sdm, /dev/sdn, /dev/sdo' > "$work/odd.json"
if run 180 plan "$work/odd.json" >/dev/null 2>&1; then
  printf 'error: storage operation accepted an invalid RAID 10 layout\n' >&2; exit 1
fi
ln -s "$work/create.json" "$work/indirect.json"
if run 190 plan "$work/indirect.json" >/dev/null 2>&1; then
  printf 'error: storage operation accepted an indirect request\n' >&2; exit 1
fi

printf 'Bedrock protected storage lifecycle and RAID recovery tests passed.\n'
