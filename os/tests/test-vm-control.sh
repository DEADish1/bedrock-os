#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
controller="$ROOT/os/config/includes.chroot/usr/lib/bedrock/control-vm"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
printf 'shut off\n' > "$work/runtime-state"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$BEDROCK_VM_TEST_LOG"
case " $* " in
  *" dominfo "*) exit 0 ;;
  *" domstate "*) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  *" start "*) printf 'running\n' > "$BEDROCK_VM_RUNTIME_STATE" ;;
  *" shutdown "*) printf 'shut off\n' > "$BEDROCK_VM_RUNTIME_STATE" ;;
  *" destroy "*) printf 'shut off\n' > "$BEDROCK_VM_RUNTIME_STATE" ;;
  *" reboot "*) printf 'running\n' > "$BEDROCK_VM_RUNTIME_STATE" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
: > "$work/virsh.log"
request() { jq -n --arg action "$1" --arg confirmation "$2" '{schema:1,name:"test-vm",action:$action,confirmation:$confirmation}' > "$work/request.json"; }
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="${BEDROCK_VM_DOMAINS_OVERRIDE:-$work/domains.json}" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_TEST_LOG="$work/virsh.log" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" "$controller" "$work/request.json"; }
request start 'START VM test-vm'; run | jq -e '.action=="start" and .previous_state=="shut off" and .state=="running"' >/dev/null
request stop 'STOP VM test-vm'; run | jq -e '.action=="stop" and .state=="shut off"' >/dev/null
printf 'running\n' > "$work/runtime-state"
request restart 'RESTART VM test-vm'; run | jq -e '.action=="restart" and .state=="running"' >/dev/null
printf 'paused\n' > "$work/runtime-state"
request force-stop 'FORCE STOP VM test-vm'; run | jq -e '.action=="force-stop" and .previous_state=="paused" and .state=="shut off"' >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
request start 'START VM other'; must_fail run
request stop 'STOP VM test-vm'; must_fail run
jq '.domains=[]' "$work/domains.json" > "$work/unmanaged.json"
request start 'START VM test-vm'
BEDROCK_VM_DOMAINS_OVERRIDE="$work/unmanaged.json" must_fail run
grep -q 'start test-vm' "$work/virsh.log"
grep -q 'shutdown test-vm --mode agent,acpi' "$work/virsh.log"
grep -q 'destroy test-vm' "$work/virsh.log"
grep -q 'reboot test-vm --mode agent,acpi' "$work/virsh.log"
printf 'VM control tests passed.\n'
