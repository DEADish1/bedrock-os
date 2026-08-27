#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
storage="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-storage"
integrity="$ROOT/os/config/includes.chroot/usr/lib/bedrock/storage-integrity"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/data"
for command in jq mktemp grep wc tr date dirname mkdir chmod mv rm rmdir; do path=$(command -v "$command"); [ -z "$path" ] || ln -s "$path" "$work/bin/$command"; done
state=$work/state.json audit=$work/audit.jsonl
req() { jq -n --arg action "$1" --arg backend zfs --arg name vault --arg pool vault --arg layout "$2" --argjson devices "$3" --arg confirmation "$4" '{schema:1,action:$action,backend:$backend,name:$name,pool:$pool,layout:$layout,devices:$devices,confirmation:$confirmation}'; }
run() { BEDROCK_STORAGE_OPERATION_TEST_MODE=1 BEDROCK_STORAGE_OPERATION_TEST_PATH="$work/bin" BEDROCK_STORAGE_OPERATION_TEST_NOW="$1" BEDROCK_STORAGE_OPERATION_TEST_AUDIT="$audit" "$storage" apply "$2" "$state"; }

req create raidz1 '["/dev/sdb","/dev/sdc","/dev/sdd"]' 'ERASE AND CREATE — vault — zfs raidz1 — /dev/sdb, /dev/sdc, /dev/sdd' > "$work/create.json"
run 100 "$work/create.json" >/dev/null
printf '%s\n' 'irreplaceable family photo bytes' > "$work/data/photo.bin"
printf '%s\n' 'important document bytes' > "$work/data/document.bin"
"$integrity" create "$work/data" "$work/integrity.json" >/dev/null
"$integrity" verify "$work/data" "$work/integrity.json" >/dev/null

req expand mirror '["/dev/sde","/dev/sdf"]' 'EXPAND — vault — /dev/sde, /dev/sdf' > "$work/expand.json"
before=$(openssl dgst -sha256 -r "$state" | awk '{print $1}')
audit_before=$(wc -l < "$audit" | tr -d ' ')
if BEDROCK_STORAGE_OPERATION_TEST_FAIL_BEFORE_COMMIT=1 run 110 "$work/expand.json" >/dev/null 2>&1; then
  printf 'error: injected storage interruption unexpectedly succeeded\n' >&2; exit 1
fi
unset BEDROCK_STORAGE_OPERATION_TEST_FAIL_BEFORE_COMMIT
after=$(openssl dgst -sha256 -r "$state" | awk '{print $1}')
[ "$before" = "$after" ] && [ "$(wc -l < "$audit" | tr -d ' ')" -eq "$audit_before" ] || { printf 'error: interrupted operation changed durable state or audit\n' >&2; exit 1; }

# Model a failed RAID-Z member reported by health collection, then perform the guarded replacement and scrub.
jq '.pools[0].state="degraded"' "$state" > "$work/degraded.json" && mv "$work/degraded.json" "$state"
req replace none '["/dev/sdb","/dev/sdg"]' 'REPLACE — vault — /dev/sdb, /dev/sdg' > "$work/replace.json"
run 120 "$work/replace.json" >/dev/null
jq -e '.pools[0].state=="rebuilding" and (.pools[0].devices|index("/dev/sdg"))' "$state" >/dev/null
req scrub none '[]' 'SCRUB — vault' > "$work/scrub.json"; run 130 "$work/scrub.json" >/dev/null
jq -e '.pools[0].state=="online" and .pools[0].last_scrub_unix==130' "$state" >/dev/null

req export none '[]' 'EXPORT — vault' > "$work/export.json"; run 140 "$work/export.json" >/dev/null
req import none '[]' 'IMPORT — vault' > "$work/import.json"; run 150 "$work/import.json" >/dev/null
"$integrity" verify "$work/data" "$work/integrity.json" >/dev/null
printf '%s\n' 'corruption' >> "$work/data/photo.bin"
if "$integrity" verify "$work/data" "$work/integrity.json" >/dev/null 2>&1; then
  printf 'error: integrity verification accepted modified data\n' >&2; exit 1
fi
printf 'Bedrock interruption, disk-failure, replacement, import, and integrity recovery tests passed.\n'
