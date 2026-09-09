#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd); wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/change-backup"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
cat > "$work/manager" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_BACKUP_CALLS"
EOF
cat > "$work/recorder" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_TASK_CALLS"
EOF
chmod +x "$work/manager" "$work/recorder"
jq -n '{schema:1,id:"nightly",operation:"run",confirmation:"RUN ENCRYPTED BACKUP nightly"}' > "$work/request.json"
run() { BEDROCK_BACKUP_ACTION_TEST_MODE=1 BEDROCK_BACKUP_ACTION_MANAGER="$work/manager" BEDROCK_TEST_BACKUP_CALLS="$work/backup-calls" BEDROCK_RECORD_API_TASK="$work/recorder" BEDROCK_TEST_TASK_CALLS="$work/task-calls" "$wrapper" "$work/request.json"; }
run
grep -Fx 'run nightly RUN ENCRYPTED BACKUP nightly' "$work/backup-calls" >/dev/null
[ "$(grep -c ' succeeded ' "$work/task-calls")" -eq 1 ]
jq -n '{schema:1,id:"nightly",operation:"restore-latest",confirmation:"RESTORE LATEST BACKUP nightly"}' > "$work/request.json"
run
grep -Fx 'restore-latest nightly RESTORE LATEST BACKUP nightly' "$work/backup-calls" >/dev/null
jq -n '{schema:1,id:"archive",operation:"create-staged",confirmation:"CREATE ENCRYPTED BACKUP archive"}' > "$work/request.json"
run
grep -Fx 'create-staged archive CREATE ENCRYPTED BACKUP archive' "$work/backup-calls" >/dev/null
[ "$(grep -c ' succeeded ' "$work/task-calls")" -eq 3 ]
jq '.confirmation="wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: invalid backup action accepted\n' >&2; exit 1; fi
printf 'Backup request wrapper tests passed.\n'
