#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd); collector="$ROOT/os/config/includes.chroot/usr/lib/bedrock/collect-remote-status"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
cat > "$work/manager" <<'EOF'
#!/bin/sh
printf '%s\n' '{"schema":1,"devices":[{"id":"42345678-1234-4123-8123-123456789abc","name":"Office laptop","created_unix":1000,"expires_unix":2000,"revoked":false,"expired":false,"last_seen_unix":null}]}'
EOF
chmod +x "$work/manager"
boot=87654321-4321-4321-8321-cba987654321; pair=12345678-1234-4123-8123-123456789abc
jq -n --arg boot "$boot" --arg id "$pair" '{schema:1,requests:[{id:$id,boot_id:$boot,client_key_sha256:("a"*64),code_sha256:("b"*64),created_monotonic:100,expires_monotonic:700,attempts:0,approved:false,used:false}],devices:[]}' > "$work/pairings.json"
run() { BEDROCK_REMOTE_STATUS_TEST_MODE=1 BEDROCK_REMOTE_STATUS_MANAGER="$work/manager" BEDROCK_REMOTE_STATUS_OUTPUT="$work/status.json" BEDROCK_REMOTE_STATUS_PAIRINGS="$work/pairings.json" BEDROCK_REMOTE_STATUS_BOOT_ID="$boot" BEDROCK_REMOTE_STATUS_MONOTONIC=200 "$collector"; }
run
jq -e --arg id "$pair" '.schema==2 and .devices[0].name=="Office laptop" and (.devices[0]|has("public_key")|not) and .pending_requests==[{id:$id,approved:false,expires_in_seconds:500}]' "$work/status.json" >/dev/null
cat > "$work/manager" <<'EOF'
#!/bin/sh
printf '%s\n' '{"schema":1,"devices":[{"id":"bad","name":"x","public_key":"leak","created_unix":1,"expires_unix":2,"revoked":false,"expired":false,"last_seen_unix":null}]}'
EOF
if run >/dev/null 2>&1; then echo "unsafe remote status accepted" >&2; exit 1; fi
jq -e '.devices[0].name=="Office laptop"' "$work/status.json" >/dev/null
printf 'Bedrock privacy-safe remote device status tests passed.\n'
