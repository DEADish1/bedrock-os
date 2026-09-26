#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
writer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/record-api-task"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
run() { now=$1; shift; BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$work" BEDROCK_API_TASK_NOW="$now" python3 "$writer" "$@"; }

for phase in journal audit tasks; do
    recovery="$work/recovery-$phase"
    BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" BEDROCK_API_TASK_NOW=600 python3 "$writer" crash-test test queued 600 0 1 steps
    code=0
    BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" BEDROCK_API_TASK_NOW=601 BEDROCK_API_TASK_CRASH_AFTER="$phase" python3 "$writer" crash-test test succeeded 600 1 1 steps || code=$?
    [ "$code" -eq 86 ]
    [ -f "$recovery/task-transaction.json" ]
    BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" python3 "$writer" --recover
    jq -e '.tasks|any(.[]; .id=="crash-test" and .state=="succeeded")' "$recovery/tasks.json" >/dev/null
    jq -e '.tasks|length==1' "$recovery/tasks.json" >/dev/null
    before=$(sha256sum "$recovery/tasks.json" "$recovery/audit.jsonl")
    BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" python3 "$writer" --recover
    [ "$before" = "$(sha256sum "$recovery/tasks.json" "$recovery/audit.jsonl")" ]
    [ ! -e "$recovery/task-transaction.json" ]
    [ "$(wc -l < "$recovery/audit.jsonl")" -eq 1 ]
    jq -e '.id=="crash-test-601" and .outcome=="succeeded"' "$recovery/audit.jsonl" >/dev/null
    BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" BEDROCK_API_TASK_NOW=603 python3 "$writer" crash-test test succeeded 600 1 1 steps
    [ "$(wc -l < "$recovery/audit.jsonl")" -eq 1 ]
done

for target in task-transaction.json audit.jsonl tasks.json; do
    recovery="$work/full-$target"
    BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" BEDROCK_API_TASK_NOW=600 python3 "$writer" full-test test queued 600 0 1 steps
    before=$(sha256sum "$recovery/tasks.json")
    if BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" BEDROCK_API_TASK_NOW=601 BEDROCK_API_TASK_FAIL_WRITE="$target" python3 "$writer" full-test test succeeded 600 1 1 steps >/dev/null 2>&1; then
        echo "injected disk-full failure was ignored" >&2; exit 1
    fi
    [ "$before" = "$(sha256sum "$recovery/tasks.json")" ]
    BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" python3 "$writer" --recover
    BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$recovery" BEDROCK_API_TASK_NOW=602 python3 "$writer" full-test test succeeded 600 1 1 steps
    jq -e '.tasks|length==1 and .[0].state=="succeeded"' "$recovery/tasks.json" >/dev/null
    [ "$(wc -l < "$recovery/audit.jsonl")" -eq 1 ]
    [ ! -e "$recovery/task-transaction.json" ]
    [ -z "$(find "$recovery" -maxdepth 1 -name '.*' -type f -print)" ]
done

retention="$work/retention"
mkdir "$retention"
jq -nc 'range(0;1000)|{id:("event-"+tostring),category:"task",action:"test",outcome:"succeeded",occurred_unix:.}' > "$retention/audit.jsonl"
BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$retention" BEDROCK_API_TASK_NOW=1001 python3 "$writer" retained test succeeded 1001 1 1 steps
[ "$(wc -l < "$retention/audit.jsonl")" -eq 1000 ]
jq -se '.[0].id=="event-1" and .[-1].id=="retained-1001"' "$retention/audit.jsonl" >/dev/null
BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$retention" BEDROCK_API_TASK_NOW=1002 python3 "$writer" retained test succeeded 1001 1 1 steps
[ "$(wc -l < "$retention/audit.jsonl")" -eq 1000 ]

run 100 update-4 update-download queued 100 0 100 bytes
run 101 update-4 update-download running 100 25 100 bytes
before=$(sha256sum "$work/tasks.json")
if run 101 update-4 update-download running 100 25 200 bytes >/dev/null 2>&1; then echo "task total changed" >&2; exit 1; fi
if run 101 update-4 update-download running 100 25 100 items >/dev/null 2>&1; then echo "task unit changed" >&2; exit 1; fi
if run 101 update-4 update-download queued 100 25 100 bytes >/dev/null 2>&1; then echo "task state regressed" >&2; exit 1; fi
[ "$before" = "$(sha256sum "$work/tasks.json")" ]
run 102 update-4 update-download succeeded 100 100 100 bytes
jq -e '.schema==1 and .generated_unix==102 and .tasks==[{id:"update-4",kind:"update-download",state:"succeeded",created_unix:100,updated_unix:102,progress:{current:100,total:100,unit:"bytes"}}]' "$work/tasks.json" >/dev/null
jq -e '.category=="task" and .action=="update-download" and .outcome=="succeeded" and .occurred_unix==102' "$work/audit.jsonl" >/dev/null
[ "$(wc -l < "$work/audit.jsonl")" -eq 1 ]
if run 103 update-4 update-download running 100 100 100 bytes >/dev/null 2>&1; then echo "terminal task changed state" >&2; exit 1; fi
if run 103 update-5 update-download running 100 101 100 bytes >/dev/null 2>&1; then echo "task exceeded total" >&2; exit 1; fi
if run 99 update-4 update-download succeeded 100 100 100 bytes >/dev/null 2>&1; then echo "task time regressed" >&2; exit 1; fi
run 200 long-upload image-upload running 200 1 100 bytes
i=1
while [ "$i" -le 255 ]; do
    run "$((200+i))" "done-$i" test succeeded "$((200+i))" 1 1 steps
    i=$((i+1))
done
run 500 newest test succeeded 500 1 1 steps
jq -e '.tasks|length==256 and any(.[]; .id=="long-upload" and .state=="running") and any(.[]; .id=="newest") and all(.[]; .id!="update-4")' "$work/tasks.json" >/dev/null
jq -n '{schema:1,generated_unix:500,tasks:[range(0;256)|{id:("active-"+tostring),kind:"test",state:"running",created_unix:500,updated_unix:500,progress:{current:0,total:1,unit:"steps"}}]}' > "$work/tasks.json"
before=$(sha256sum "$work/tasks.json")
if run 501 overflow test queued 501 0 1 steps >/dev/null 2>&1; then echo "active task capacity exceeded" >&2; exit 1; fi
[ "$before" = "$(sha256sum "$work/tasks.json")" ]
run 502 active-0 test succeeded 500 1 1 steps
jq -e '.tasks|length==256 and any(.[]; .id=="active-0" and .state=="succeeded")' "$work/tasks.json" >/dev/null
run 503 admitted test queued 503 0 1 steps
jq -e '.tasks|length==256 and all(.[]; .state=="queued" or .state=="running") and any(.[]; .id=="admitted")' "$work/tasks.json" >/dev/null
printf '{"schema":1,"generated_unix":1,"tasks":[{"id":"bad"}]}\n' > "$work/tasks.json"
if run 104 update-6 update-download queued 104 0 100 bytes >/dev/null 2>&1; then echo "malformed prior state accepted" >&2; exit 1; fi
rm "$work/tasks.json"
ln -s "$work/missing-task-target" "$work/tasks.json"
if run 504 unsafe test queued 504 0 1 steps >/dev/null 2>&1; then echo "dangling task symlink accepted" >&2; exit 1; fi
[ -L "$work/tasks.json" ] && [ ! -e "$work/missing-task-target" ]
rm "$work/tasks.json" "$work/tasks.lock"
printf 'protected\n' > "$work/lock-target"
chmod 644 "$work/lock-target"
ln -s "$work/lock-target" "$work/tasks.lock"
if run 504 unsafe test queued 504 0 1 steps >/dev/null 2>&1; then echo "indirect lock accepted" >&2; exit 1; fi
[ "$(stat -c %a "$work/lock-target")" = 644 ]
[ "$(cat "$work/lock-target")" = protected ]
rm "$work/tasks.lock" "$work/audit.jsonl"
ln -s "$work/missing-audit-target" "$work/audit.jsonl"
if run 504 unsafe test succeeded 504 1 1 steps >/dev/null 2>&1; then echo "dangling audit symlink accepted" >&2; exit 1; fi
[ ! -e "$work/tasks.json" ] && [ ! -e "$work/missing-audit-target" ]
ln -s "$work/elsewhere" "$work/unsafe"
if BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$work/unsafe" python3 "$writer" x test queued 1 0 1 steps >/dev/null 2>&1; then echo "indirect state directory accepted" >&2; exit 1; fi

printf 'Bedrock API task-state and audit producer tests passed.\n'
