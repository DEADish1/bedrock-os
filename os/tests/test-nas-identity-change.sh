#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd); wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/change-nas-identity"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM; mkdir -p "$work/requests"
cat > "$work/manager" <<'EOF'
#!/bin/sh
cat "$1" >> "$BEDROCK_NAS_ACTION_CALLS"
EOF
chmod +x "$work/manager"
cat > "$work/task-writer" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_NAS_TASK_CALLS"
EOF
chmod +x "$work/task-writer"
run() { BEDROCK_NAS_ACTION_TEST_MODE=1 BEDROCK_NAS_ACTION_MANAGER="$work/manager" BEDROCK_NAS_ACTION_OUTPUT="$work/requests/operation.json" BEDROCK_NAS_ACTION_CALLS="$work/calls" BEDROCK_RECORD_API_TASK="$work/task-writer" BEDROCK_NAS_TASK_CALLS="$work/task-calls" "$wrapper" "$work/request.json"; }
jq -n '{schema:1,id:"alice",operation:"create-user",confirmation:"CREATE NAS USER alice"}' > "$work/request.json"; run
jq -e '.action=="create-user" and .name=="alice" and .confirmation=="CREATE USER — alice" and .protocols==[]' "$work/calls" >/dev/null
jq -n '{schema:1,id:"family",operation:"create-group",confirmation:"CREATE NAS GROUP family"}' > "$work/request.json"; run
jq -s -e '.[1].action=="create-group" and .[1].name=="family" and .[1].confirmation=="CREATE GROUP — family"' "$work/calls" >/dev/null
jq -n '{schema:1,id:"family",subject:"alice",operation:"add-member",confirmation:"ADD NAS USER alice TO GROUP family"}' > "$work/request.json"; run
jq -s -e '.[2].action=="add-member" and .[2].name=="family" and .[2].subject=="alice" and .[2].confirmation=="ADD MEMBER — alice — family"' "$work/calls" >/dev/null
printf '%s\n' 'correct horse battery staple' > "$work/password"
jq -n '{schema:1,id:"alice",operation:"rotate-staged",confirmation:"ROTATE NAS CREDENTIAL alice"}' > "$work/request.json"
BEDROCK_NAS_ACTION_PASSWORD_FILE="$work/password" run
jq -s -e '.[3].action=="rotate-credential" and .[3].name=="alice" and .[3].confirmation=="ROTATE CREDENTIAL — alice"' "$work/calls" >/dev/null
[ ! -e "$work/password" ]
[ "$(grep -c ' succeeded ' "$work/task-calls")" -eq 4 ]
jq '.confirmation="wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"; if run >/dev/null 2>&1; then printf 'error: invalid NAS identity action accepted\n' >&2; exit 1; fi
printf 'NAS identity action wrapper tests passed.\n'
