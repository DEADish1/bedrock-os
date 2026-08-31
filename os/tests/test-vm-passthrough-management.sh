#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manager="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-vm-passthrough"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
jq -n '{schema:2,gpus:[{pci_address:"0000:03:00.0",boot_vga:false,iommu_group:"17",iommu_group_devices:["0000:03:00.0","0000:03:00.1"]}],usb_devices:[{id:"1-2",authorized:true,host_critical:false,busnum:1,devnum:4}]}' > "$work/hardware.json"
jq -n '{schema:1,assignments:[]}' > "$work/passthrough.json"
jq -S -n '{schema:1,status:"review-only",mutation_authorized:false,vm:"test-vm",kind:"gpu",devices:["0000:03:00.0","0000:03:00.1"],iommu_group:"17",warnings:["warning one","warning two"]}' > "$work/plan.json"
hash=$(sha256sum "$work/plan.json" | awk '{print $1}')
printf 'shut off\n' > "$work/runtime-state"; printf '0\n' > "$work/hostdev-count"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
case "$3" in
  dominfo) exit 0 ;;
  domstate) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  dumpxml) count=$(cat "$BEDROCK_VM_HOSTDEV_COUNT"); printf '<domain><devices>'; i=0; while [ "$i" -lt "$count" ]; do printf "<hostdev type='pci'/>"; i=$((i+1)); done; printf '</devices></domain>\n' ;;
  attach-device) count=$(cat "$BEDROCK_VM_HOSTDEV_COUNT"); printf '%s\n' $((count+1)) > "$BEDROCK_VM_HOSTDEV_COUNT" ;;
  detach-device) count=$(cat "$BEDROCK_VM_HOSTDEV_COUNT"); printf '%s\n' $((count-1)) > "$BEDROCK_VM_HOSTDEV_COUNT" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
authorize() { jq -n --arg action "$1" --arg hash "$hash" --arg confirmation "$2" '{schema:1,action:$action,vm:"test-vm",kind:"gpu",plan_sha256:$hash,confirmation:$confirmation}' > "$work/auth.json"; }
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_PASSTHROUGH="$work/passthrough.json" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_HARDWARE="$work/hardware.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" BEDROCK_VM_HOSTDEV_COUNT="$work/hostdev-count" "$manager" "$work/plan.json" "$work/auth.json"; }
authorize assign 'ASSIGN GPU PASSTHROUGH VM test-vm DEVICES 0000:03:00.0,0000:03:00.1'; run | jq -e '.action=="assign" and (.devices|length)==2' >/dev/null
[ "$(cat "$work/hostdev-count")" -eq 2 ]; jq -e '.assignments|length==1' "$work/passthrough.json" >/dev/null
authorize remove 'REMOVE GPU PASSTHROUGH VM test-vm DEVICES 0000:03:00.0,0000:03:00.1'; run | jq -e '.action=="remove"' >/dev/null
[ "$(cat "$work/hostdev-count")" -eq 0 ]; jq -e '.assignments==[]' "$work/passthrough.json" >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail run
authorize assign 'ASSIGN GPU PASSTHROUGH VM wrong DEVICES 0000:03:00.0,0000:03:00.1'; must_fail run
jq -S -n '{schema:1,status:"review-only",mutation_authorized:false,vm:"test-vm",kind:"usb",devices:["1-2"],iommu_group:null,warnings:["warning one","warning two"]}' > "$work/plan.json"
hash=$(sha256sum "$work/plan.json" | awk '{print $1}')
authorize() { jq -n --arg action "$1" --arg hash "$hash" --arg confirmation "$2" '{schema:1,action:$action,vm:"test-vm",kind:"usb",plan_sha256:$hash,confirmation:$confirmation}' > "$work/auth.json"; }
authorize assign 'ASSIGN USB PASSTHROUGH VM test-vm DEVICES 1-2'; run | jq -e '.kind=="usb" and .action=="assign"' >/dev/null
[ "$(cat "$work/hostdev-count")" -eq 1 ]
authorize remove 'REMOVE USB PASSTHROUGH VM test-vm DEVICES 1-2'; run | jq -e '.kind=="usb" and .action=="remove"' >/dev/null
[ "$(cat "$work/hostdev-count")" -eq 0 ]
printf 'VM passthrough management tests passed.\n'
