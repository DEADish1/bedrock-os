#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
helper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/change-vm-passthrough"
planner="$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-passthrough-plan"
manager="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-vm-passthrough"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
jq -n '{schema:2,gpus:[],usb_devices:[{id:"1-2",authorized:true,host_critical:false,device_class:"00",busnum:1,devnum:4}]}' > "$work/hardware.json"
jq -n '{schema:1,assignments:[]}' > "$work/passthrough.json"
printf 'shut off\n' > "$work/runtime-state"; printf '0\n' > "$work/hostdev-count"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
case "$3" in
  dominfo) exit 0 ;;
  domstate) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  dumpxml) count=$(cat "$BEDROCK_VM_HOSTDEV_COUNT"); printf '<domain><devices>'; while [ "$count" -gt 0 ]; do printf "<hostdev type='usb'/>"; count=$((count-1)); done; printf '</devices></domain>\n' ;;
  attach-device) count=$(cat "$BEDROCK_VM_HOSTDEV_COUNT"); printf '%s\n' $((count+1)) > "$BEDROCK_VM_HOSTDEV_COUNT" ;;
  detach-device) count=$(cat "$BEDROCK_VM_HOSTDEV_COUNT"); printf '%s\n' $((count-1)) > "$BEDROCK_VM_HOSTDEV_COUNT" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
make_request() { jq -S -n --arg action "$1" '{schema:1,vm:"test-vm",kind:"usb",devices:["1-2"],action:$action,review_confirmation:"REVIEW USB PASSTHROUGH VM test-vm DEVICES 1-2",confirmation:(($action|ascii_upcase)+" USB PASSTHROUGH VM test-vm DEVICES 1-2")}' > "$work/request.json"; }
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_PASSTHROUGH_PLANNER="$planner" BEDROCK_VM_PASSTHROUGH_MANAGER="$manager" BEDROCK_VM_HARDWARE="$work/hardware.json" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_PASSTHROUGH="$work/passthrough.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" BEDROCK_VM_HOSTDEV_COUNT="$work/hostdev-count" "$helper" "$work/request.json"; }
make_request assign; run | jq -e '.status=="completed" and .action=="assign"' >/dev/null
[ "$(cat "$work/hostdev-count")" -eq 1 ]
[ ! -e "$work/state/plans/test-vm-usb-passthrough.json" ]
make_request remove; run | jq -e '.status=="completed" and .action=="remove"' >/dev/null
[ "$(cat "$work/hostdev-count")" -eq 0 ]
jq '.confirmation="ASSIGN USB PASSTHROUGH VM wrong DEVICES 1-2"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: invalid confirmation was accepted\n' >&2; exit 1; fi
printf 'VM passthrough change tests passed.\n'
