#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd); wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/change-app"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
cat > "$work/manager" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_APP_CALLS"
EOF
cat > "$work/recorder" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_TASK_CALLS"
EOF
chmod +x "$work/manager" "$work/recorder"
run() { BEDROCK_APP_ACTION_TEST_MODE=1 BEDROCK_APP_ACTION_MANAGER="$work/manager" BEDROCK_TEST_APP_CALLS="$work/app-calls" BEDROCK_RECORD_API_TASK="$work/recorder" BEDROCK_TEST_TASK_CALLS="$work/task-calls" "$wrapper" "$work/request.json"; }
jq -n '{schema:1,id:"photos",operation:"stop",confirmation:"STOP APPLICATION photos"}' > "$work/request.json"; run
jq -n '{schema:1,id:"photos",operation:"start",confirmation:"START APPLICATION photos"}' > "$work/request.json"; run
[ "$(grep -c ' succeeded ' "$work/task-calls")" -eq 2 ]; grep -Fx 'stop photos STOP APPLICATION photos' "$work/app-calls" >/dev/null; grep -Fx 'start photos START APPLICATION photos' "$work/app-calls" >/dev/null
jq '.confirmation="wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: invalid application action accepted\n' >&2; exit 1; fi
printf 'Application request wrapper tests passed.\n'
