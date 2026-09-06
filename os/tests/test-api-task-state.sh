#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
writer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/record-api-task"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
run() { now=$1; shift; BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$work" BEDROCK_API_TASK_NOW="$now" python3 "$writer" "$@"; }

run 100 update-4 update-download queued 100 0 100 bytes
run 101 update-4 update-download running 100 25 100 bytes
run 102 update-4 update-download succeeded 100 100 100 bytes
jq -e '.schema==1 and .generated_unix==102 and .tasks==[{id:"update-4",kind:"update-download",state:"succeeded",created_unix:100,updated_unix:102,progress:{current:100,total:100,unit:"bytes"}}]' "$work/tasks.json" >/dev/null
jq -e '.category=="task" and .action=="update-download" and .outcome=="succeeded" and .occurred_unix==102' "$work/audit.jsonl" >/dev/null
[ "$(wc -l < "$work/audit.jsonl")" -eq 1 ]
if run 103 update-4 update-download running 100 100 100 bytes >/dev/null 2>&1; then echo "terminal task changed state" >&2; exit 1; fi
if run 103 update-5 update-download running 100 101 100 bytes >/dev/null 2>&1; then echo "task exceeded total" >&2; exit 1; fi
if run 99 update-4 update-download succeeded 100 100 100 bytes >/dev/null 2>&1; then echo "task time regressed" >&2; exit 1; fi
printf '{"schema":1,"generated_unix":1,"tasks":[{"id":"bad"}]}\n' > "$work/tasks.json"
if run 104 update-6 update-download queued 104 0 100 bytes >/dev/null 2>&1; then echo "malformed prior state accepted" >&2; exit 1; fi
rm "$work/tasks.json"
ln -s "$work/elsewhere" "$work/unsafe"
if BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$work/unsafe" python3 "$writer" x test queued 1 0 1 steps >/dev/null 2>&1; then echo "indirect state directory accepted" >&2; exit 1; fi

printf 'Bedrock API task-state and audit producer tests passed.\n'
