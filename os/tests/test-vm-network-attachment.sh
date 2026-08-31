#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manager="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-vm-network-attachment"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
jq -n '{schema:1,networks:[{name:"lab",libvirt_name:"bedrock-lab",bridge:"br-bedrock-42",cidr:"10.240.42.0/24",subnet_octet:42}]}' > "$work/networks.json"
jq -n '{schema:1,attachments:[]}' > "$work/attachments.json"
printf 'shut off\n' > "$work/runtime-state"; : > "$work/interfaces"; : > "$work/virsh.log"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$BEDROCK_VM_TEST_LOG"
case "$3" in
  dominfo) exit 0 ;;
  domstate) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  net-info) printf 'Name: %s\nActive: yes\nAutostart: yes\n' "$4" ;;
  domiflist) printf '%s\n' 'Interface Type Source Model MAC' '--------------------------------'; cat "$BEDROCK_VM_INTERFACES" ;;
  attach-device) mac=$(sed -n "s/.*mac address='\([^']*\)'.*/\1/p" "$5"); source=$(sed -n "s/.*source network='\([^']*\)'.*/\1/p" "$5"); printf 'vnet0 network %s virtio %s\n' "$source" "$mac" >> "$BEDROCK_VM_INTERFACES" ;;
  detach-device) mac=$(sed -n "s/.*mac address='\([^']*\)'.*/\1/p" "$5"); awk -v mac="$mac" 'tolower($5)!=mac' "$BEDROCK_VM_INTERFACES" > "$BEDROCK_VM_INTERFACES.tmp"; mv "$BEDROCK_VM_INTERFACES.tmp" "$BEDROCK_VM_INTERFACES" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
request() { jq -n --arg action "$1" --arg confirmation "$2" '{schema:1,vm:"test-vm",network:"lab",action:$action,confirmation:$confirmation}' > "$work/request.json"; }
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_NETWORKS="$work/networks.json" BEDROCK_VM_NETWORK_ATTACHMENTS="$work/attachments.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_TEST_LOG="$work/virsh.log" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" BEDROCK_VM_INTERFACES="$work/interfaces" "$manager" "$work/request.json"; }
request attach 'ATTACH NETWORK lab TO VM test-vm'; run | jq -e '.model=="virtio" and (.mac|startswith("52:54:00:"))' >/dev/null
jq -e '.attachments|length==1 and .[0].network=="lab"' "$work/attachments.json" >/dev/null
request detach 'DETACH NETWORK lab FROM VM test-vm'; run | jq -e '.action=="detach"' >/dev/null
jq -e '.attachments==[]' "$work/attachments.json" >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail run
request attach 'ATTACH NETWORK wrong TO VM test-vm'; must_fail run
printf 'running\n' > "$work/runtime-state"; request attach 'ATTACH NETWORK lab TO VM test-vm'; must_fail run
printf 'VM network attachment tests passed.\n'
