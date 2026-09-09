#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd); wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/change-vm-image"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
hash=$(printf source | sha256sum | awk '{print $1}')
cat > "$work/converter" <<'EOF'
#!/bin/sh
cat "$1" >> "$BEDROCK_TEST_IMAGE_CALLS"
EOF
cat > "$work/recorder" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_TASK_CALLS"
EOF
chmod +x "$work/converter" "$work/recorder"
jq -n --arg hash "$hash" '{schema:1,source:"source",source_sha256:$hash,target:"converted",target_type:"qcow2",confirmation:("CONVERT IMAGE source "+$hash+" TO QCOW2 converted")}' > "$work/request.json"
run() { BEDROCK_IMAGE_ACTION_TEST_MODE=1 BEDROCK_IMAGE_ACTION_CONVERTER="$work/converter" BEDROCK_TEST_IMAGE_CALLS="$work/image-calls" BEDROCK_RECORD_API_TASK="$work/recorder" BEDROCK_TEST_TASK_CALLS="$work/task-calls" "$wrapper" "$work/request.json"; }
run
jq -e '.source=="source" and .target=="converted" and .target_type=="qcow2"' "$work/image-calls" >/dev/null
[ "$(grep -c ' succeeded ' "$work/task-calls")" -eq 1 ]
jq '.confirmation="wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: invalid image conversion accepted\n' >&2; exit 1; fi
printf 'Image conversion request wrapper tests passed.\n'
