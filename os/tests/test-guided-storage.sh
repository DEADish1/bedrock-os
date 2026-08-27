#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
guided="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-storage-guided"
dialog_fixture="$ROOT/os/tests/fixtures/guided-installer"
executor="$ROOT/os/tests/fixtures/guided-storage/executor"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
jq -n '{schema:1,generated_unix:1,overall:"healthy",read_only:true,disks:[
  {path:"/dev/sdb",size_bytes:1000000000000,model:"Disk B",smart:{health:"healthy",temperature_c:31}},
  {path:"/dev/sdc",size_bytes:1000000000000,model:"Disk C",smart:{health:"healthy",temperature_c:32}}]}' > "$work/health.json"
printf '%s\n' '{"schema":1,"pools":[]}' > "$work/state.json"
run() {
  BEDROCK_STORAGE_GUIDED_TEST_MODE=1 BEDROCK_STORAGE_GUIDED_TEST_PATH="$dialog_fixture:$PATH" \
  BEDROCK_STORAGE_GUIDED_TEST_HEALTH="$work/health.json" BEDROCK_STORAGE_GUIDED_TEST_STATE="$work/state.json" \
  BEDROCK_STORAGE_GUIDED_TEST_EXECUTOR="$executor" BEDROCK_STORAGE_GUIDED_TEST_LOG="$work/log" \
  BEDROCK_TEST_DIALOG_RESPONSES="$work/responses" "$guided"
}
confirmation='ERASE AND CREATE — vault — zfs mirror — /dev/sdb, /dev/sdc'
printf 'create\nvault\nzfs\nmirror\n/dev/sdb\n/dev/sdc\ndone\n%s\n' "$confirmation" > "$work/responses"
: > "$work/log"; run
grep -q '^plan create vault$' "$work/log" && grep -q '^apply create vault$' "$work/log"
[ ! -s "$work/responses" ]
printf 'create\nvault\nzfs\nmirror\n/dev/sdb\n/dev/sdc\ndone\nWRONG\n' > "$work/responses"
: > "$work/log"
if run >/dev/null 2>&1; then printf 'error: guided storage accepted an incorrect confirmation\n' >&2; exit 1; fi
[ ! -s "$work/log" ]
printf 'Bedrock terminal-free guided storage workflow tests passed.\n'
