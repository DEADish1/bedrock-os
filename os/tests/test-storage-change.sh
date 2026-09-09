#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/change-storage"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/requests"
jq -n '{schema:1,pools:[{name:"vault",backend:"zfs",layout:"mirror",devices:["/dev/sdb","/dev/sdc"],state:"online",last_scrub_unix:null,last_operation_unix:1}]}' > "$work/state.json"
cat > "$work/manager" <<'EOF'
#!/bin/sh
cat "$1" >> "$BEDROCK_STORAGE_ACTION_CALLS"
EOF
chmod +x "$work/manager"
run() { BEDROCK_STORAGE_ACTION_TEST_MODE=1 BEDROCK_STORAGE_ACTION_MANAGER="$work/manager" BEDROCK_STORAGE_ACTION_STATE="$work/state.json" BEDROCK_STORAGE_ACTION_OUTPUT="$work/requests/operation.json" BEDROCK_STORAGE_ACTION_CALLS="$work/calls" "$wrapper" "$work/request.json"; }
jq -n '{schema:1,id:"vault",operation:"scrub",confirmation:"SCRUB STORAGE vault"}' > "$work/request.json"
run
jq -e '.schema==1 and .action=="scrub" and .backend=="zfs" and .pool=="vault" and .devices==[] and .confirmation=="SCRUB — vault"' "$work/calls" >/dev/null
[ ! -e "$work/requests/operation.json" ]
jq '.confirmation="wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: invalid storage action accepted\n' >&2; exit 1; fi
jq -n '{schema:1,id:"missing",operation:"scrub",confirmation:"SCRUB STORAGE missing"}' > "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: unknown storage accepted\n' >&2; exit 1; fi
printf 'Storage action wrapper tests passed.\n'
