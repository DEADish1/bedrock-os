#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
deleter="$ROOT/os/config/includes.chroot/usr/lib/bedrock/delete-vm"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin"
setup() {
  rm -rf "$work/state"
  mkdir -p "$work/state/definitions" "$work/state/plans" "$work/state/authorizations" "$work/state/disks"
  printf '<domain/>\n' > "$work/state/definitions/test-vm.xml"
  printf '{}\n' > "$work/state/plans/test-vm.json"
  printf '{}\n' > "$work/state/authorizations/test-vm.json"
  printf 'disk\n' > "$work/state/disks/test-vm.qcow2"
  jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/state/domains.json"
  hash=$(sha256sum "$work/state/definitions/test-vm.xml" | awk '{print $1}')
  jq -n --arg hash "$hash" '{schema:1,action:"delete",name:"test-vm",confirmation:"DELETE VM test-vm AND STORAGE",definition_sha256:$hash}' > "$work/request.json"
  printf 'shut off\n' > "$work/runtime-state"
  : > "$work/virsh.log"
}
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$BEDROCK_VM_TEST_LOG"
case " $* " in
  *" dominfo "*) exit 0 ;;
  *" domstate "*) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  *" undefine "*) [ "${BEDROCK_VM_FAIL_UNDEFINE:-0}" != 1 ] ;;
  *" define "*) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/state/domains.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_TEST_LOG="$work/virsh.log" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" "$deleter" "$work/request.json"; }
setup
run | jq -e '.status=="deleted-recoverable" and .running==false' >/dev/null
jq -e '.domains==[]' "$work/state/domains.json" >/dev/null
[ ! -e "$work/state/disks/test-vm.qcow2" ]
[ -f "$work/state/quarantine/test-vm/disk.qcow2" ]
[ -f "$work/state/quarantine/test-vm/domains.before.json" ]
grep -q 'undefine test-vm --nvram' "$work/virsh.log"
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
setup
printf 'running\n' > "$work/runtime-state"
must_fail run
[ -f "$work/state/disks/test-vm.qcow2" ]
setup
jq '.confirmation="DELETE VM other AND STORAGE"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
must_fail run
setup
BEDROCK_VM_FAIL_UNDEFINE=1 must_fail run
[ -f "$work/state/disks/test-vm.qcow2" ]
[ -f "$work/state/definitions/test-vm.xml" ]
jq -e '.domains|length==1' "$work/state/domains.json" >/dev/null
[ ! -e "$work/state/quarantine/test-vm" ]
printf 'VM deletion tests passed.\n'
