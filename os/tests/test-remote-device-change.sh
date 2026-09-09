#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/change-remote-device"; manager="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-remote-devices"
python=${BEDROCK_TEST_PYTHON:-python3}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/tasks"; id=42345678-1234-4123-8123-123456789abc; key=$(printf client | sha256sum | awk '{print $1}'); hash=$(printf '%s' "$key" | xxd -r -p | sha256sum | awk '{print $1}')
jq -n --arg id "$id" --arg key "$key" --arg hash "$hash" '{schema:1,requests:[],devices:[{id:$id,name:"New device",public_key:$key,public_key_sha256:$hash,created_unix:1000,expires_unix:3000,revoked:false,last_seen_unix:null}]}' > "$work/pairings.json"
cat > "$work/terminator" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$work/terminator"
cat > "$work/manager" <<'EOF'
#!/bin/sh
exec "$BEDROCK_TEST_PYTHON" "$BEDROCK_TEST_REAL_MANAGER" "$@"
EOF
chmod +x "$work/manager"
cat > "$work/recorder" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_TASK_CALLS"
EOF
chmod +x "$work/recorder"
cat > "$work/collector" <<'EOF'
#!/bin/sh
printf 'refresh\n' >> "$BEDROCK_TEST_STATUS_CALLS"
EOF
chmod +x "$work/collector"
run() { BEDROCK_PAIRING_TEST_MODE=1 BEDROCK_PAIRING_STATE_DIR="$work" BEDROCK_PAIRING_TEST_WALL_NOW=1100 BEDROCK_PAIRING_SESSION_TERMINATOR="$work/terminator" BEDROCK_REMOTE_DEVICE_MANAGER="$work/manager" BEDROCK_TEST_REAL_MANAGER="$manager" BEDROCK_TEST_PYTHON="$python" BEDROCK_REMOTE_STATUS_COLLECTOR="$work/collector" BEDROCK_TEST_STATUS_CALLS="$work/status-calls" BEDROCK_RECORD_API_TASK="$work/recorder" BEDROCK_TEST_TASK_CALLS="$work/task-calls" "$wrapper" "$work/request.json"; }
jq -n --arg id "$id" '{schema:1,id:$id,operation:"rename",name:"Office laptop"}' > "$work/request.json"; run | jq -e '.action=="rename"' >/dev/null
jq -n --arg id "$id" '{schema:1,id:$id,operation:"expire",expires_unix:2000,confirmation:("EXPIRE REMOTE DEVICE "+$id+" AT 2000")}' > "$work/request.json"; run | jq -e '.action=="expire"' >/dev/null
jq -n --arg id "$id" '{schema:1,id:$id,operation:"revoke",confirmation:("REVOKE REMOTE DEVICE "+$id)}' > "$work/request.json"; run | jq -e '.action=="revoke"' >/dev/null
jq -e '.devices[0].name=="Office laptop" and .devices[0].expires_unix==2000 and .devices[0].revoked==true' "$work/pairings.json" >/dev/null
[ "$(grep -c ' succeeded ' "$work/task-calls")" -eq 3 ]
[ "$(wc -l < "$work/status-calls" | tr -d ' ')" -eq 3 ]
jq '.confirmation="REVOKE REMOTE DEVICE wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: invalid confirmation accepted\n' >&2; exit 1; fi
printf 'Remote device request wrapper tests passed.\n'
