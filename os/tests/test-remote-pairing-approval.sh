#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd); wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/approve-remote-pairing"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
id=12345678-1234-4123-8123-123456789abc
cat > "$work/manager" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_PAIRING_CALLS"
printf '%s\n' '{"schema":1,"status":"approved"}'
EOF
cat > "$work/recorder" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_TASK_CALLS"
EOF
chmod +x "$work/manager" "$work/recorder"
cat > "$work/collector" <<'EOF'
#!/bin/sh
printf 'refresh\n' >> "$BEDROCK_TEST_STATUS_CALLS"
EOF
chmod +x "$work/collector"
jq -n --arg id "$id" '{schema:1,id:$id,confirmation:("APPROVE REMOTE DEVICE "+$id)}' > "$work/request.json"
run() { BEDROCK_PAIRING_TEST_MODE=1 BEDROCK_REMOTE_PAIRING_MANAGER="$work/manager" BEDROCK_REMOTE_STATUS_COLLECTOR="$work/collector" BEDROCK_TEST_STATUS_CALLS="$work/status-calls" BEDROCK_RECORD_API_TASK="$work/recorder" BEDROCK_TEST_PAIRING_CALLS="$work/pairing-calls" BEDROCK_TEST_TASK_CALLS="$work/task-calls" "$wrapper" "$work/request.json"; }
run | jq -e '.status=="approved"' >/dev/null
grep -Fx "approve $id APPROVE REMOTE DEVICE $id" "$work/pairing-calls" >/dev/null
[ "$(grep -c ' succeeded ' "$work/task-calls")" -eq 1 ]
grep -Fx refresh "$work/status-calls" >/dev/null
jq '.confirmation="APPROVE REMOTE DEVICE wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: invalid pairing approval accepted\n' >&2; exit 1; fi
printf 'Remote pairing approval wrapper tests passed.\n'
