#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
collector="$ROOT/os/config/includes.chroot/usr/lib/bedrock/collect-vm-status"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
jq -n '{schema:1,attachments:[{vm:"test-vm",image:"installer",type:"iso",device:"cdrom",target:"sda",path:"/images/installer.iso"}]}' > "$work/images.json"
jq -n '{schema:1,attachments:[{vm:"test-vm",network:"lab",libvirt_name:"bedrock-lab",mac:"52:54:00:00:00:01"}]}' > "$work/networks.json"
printf 'shut off\n' > "$work/runtime-state"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
case "$3" in
  dominfo) printf 'Name: test-vm\nAutostart: enable\n' ;;
  domstate) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  snapshot-list) printf 'clean-install\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_ATTACHMENTS="$work/images.json" BEDROCK_VM_NETWORK_ATTACHMENTS="$work/networks.json" BEDROCK_VM_STATUS="$work/state/status.json" BEDROCK_VM_AUDIT="$work/state/audit.jsonl" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" BEDROCK_VM_NOW="$1" "$collector"; }
run 100 | jq -e '.domains==[{autostart:true,image_attachments:["installer"],memory_mib:8192,name:"test-vm",network_attachments:["lab"],snapshot_count:1,state:"shut off",vcpus:4}]' >/dev/null
jq -e '.event=="observed" and .timestamp_unix==100' "$work/state/audit.jsonl" >/dev/null
run 101 >/dev/null
[ "$(wc -l < "$work/state/audit.jsonl")" -eq 1 ]
printf 'running\n' > "$work/runtime-state"
run 102 | jq -e '.domains[0].state=="running"' >/dev/null
[ "$(wc -l < "$work/state/audit.jsonl")" -eq 2 ]
tail -n 1 "$work/state/audit.jsonl" | jq -e '.event=="lifecycle-changed" and .previous_state=="shut off" and .state=="running"' >/dev/null
printf 'VM status tests passed.\n'
