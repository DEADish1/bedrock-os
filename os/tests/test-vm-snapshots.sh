#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manager="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-vm-snapshot"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state/disks"
printf 'disk\n' > "$work/state/disks/test-vm.qcow2"
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
printf 'shut off\n' > "$work/runtime-state"
: > "$work/snapshots"
: > "$work/virsh.log"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$BEDROCK_VM_TEST_LOG"
command=$3
case "$command" in
  dominfo) exit 0 ;;
  domstate) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  snapshot-list) cat "$BEDROCK_VM_SNAPSHOTS" ;;
  snapshot-create-as) printf '%s\n' "$5" >> "$BEDROCK_VM_SNAPSHOTS" ;;
  snapshot-revert) exit 0 ;;
  snapshot-delete) grep -Fvx "$5" "$BEDROCK_VM_SNAPSHOTS" > "$BEDROCK_VM_SNAPSHOTS.tmp" || true; mv "$BEDROCK_VM_SNAPSHOTS.tmp" "$BEDROCK_VM_SNAPSHOTS" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
request() { jq -n --arg action "$1" --arg confirmation "$2" '{schema:1,name:"test-vm",snapshot:"before-upgrade",action:$action,confirmation:$confirmation}' > "$work/request.json"; }
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_TEST_LOG="$work/virsh.log" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" BEDROCK_VM_SNAPSHOTS="$work/snapshots" "$manager" "$work/request.json"; }
request create 'CREATE SNAPSHOT before-upgrade FOR VM test-vm'; run | jq -e '.action=="create" and .state=="shut off"' >/dev/null
grep -Fxq before-upgrade "$work/snapshots"
request restore 'RESTORE SNAPSHOT before-upgrade FOR VM test-vm'; run | jq -e '.action=="restore" and .snapshot=="before-upgrade"' >/dev/null
request delete 'DELETE SNAPSHOT before-upgrade FOR VM test-vm'; run | jq -e '.action=="delete"' >/dev/null
[ ! -s "$work/snapshots" ]
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
request restore 'RESTORE SNAPSHOT before-upgrade FOR VM test-vm'; must_fail run
request create 'CREATE SNAPSHOT wrong FOR VM test-vm'; must_fail run
printf 'running\n' > "$work/runtime-state"
request create 'CREATE SNAPSHOT before-upgrade FOR VM test-vm'; must_fail run
grep -q 'snapshot-create-as test-vm before-upgrade' "$work/virsh.log"
grep -q 'snapshot-revert test-vm before-upgrade' "$work/virsh.log"
grep -q 'snapshot-delete test-vm before-upgrade' "$work/virsh.log"
printf 'VM snapshot tests passed.\n'
