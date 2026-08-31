#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manager="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-vm-image-attachment"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state/images"
state_root=$work/state
[ -z "${MSYSTEM:-}" ] || state_root=$(cygpath -m "$work/state")
printf 'iso-data\n' > "$work/state/images/installer.iso"
hash=$(sha256sum "$work/state/images/installer.iso" | awk '{print $1}')
size=$(stat -c %s "$work/state/images/installer.iso")
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
jq -n --arg hash "$hash" --argjson size "$size" --arg path "$state_root/images/installer.iso" '{schema:1,images:[{name:"installer",type:"iso",sha256:$hash,size_bytes:$size,path:$path}]}' > "$work/images.json"
jq -n '{schema:1,attachments:[]}' > "$work/attachments.json"
printf 'shut off\n' > "$work/runtime-state"; : > "$work/blocks"; : > "$work/virsh.log"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$BEDROCK_VM_TEST_LOG"
case "$3" in
  dominfo) exit 0 ;;
  domstate) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  domblklist) printf '%s\n' 'Type Device Target Source' '--------------------------------'; cat "$BEDROCK_VM_BLOCKS" ;;
  attach-device) target=$(sed -n "s/.*target dev='\([^']*\)'.*/\1/p" "$5"); source=$(sed -n "s/.*source file='\([^']*\)'.*/\1/p" "$5"); printf 'file cdrom %s %s\n' "$target" "$source" >> "$BEDROCK_VM_BLOCKS" ;;
  detach-device) target=$(sed -n "s/.*target dev='\([^']*\)'.*/\1/p" "$5"); awk -v target="$target" '$3!=target' "$BEDROCK_VM_BLOCKS" > "$BEDROCK_VM_BLOCKS.tmp"; mv "$BEDROCK_VM_BLOCKS.tmp" "$BEDROCK_VM_BLOCKS" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
request() { jq -n --arg action "$1" --arg confirmation "$2" '{schema:1,vm:"test-vm",image:"installer",action:$action,confirmation:$confirmation}' > "$work/request.json"; }
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$state_root" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_IMAGES="$work/images.json" BEDROCK_VM_ATTACHMENTS="$work/attachments.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_TEST_LOG="$work/virsh.log" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" BEDROCK_VM_BLOCKS="$work/blocks" "$manager" "$work/request.json"; }
request attach 'ATTACH IMAGE installer TO VM test-vm'; run | jq -e '.device=="cdrom" and .target=="sda" and .read_only==true' >/dev/null
jq -e '.attachments|length==1 and .[0].image=="installer"' "$work/attachments.json" >/dev/null
request detach 'DETACH IMAGE installer FROM VM test-vm'; run | jq -e '.action=="detach"' >/dev/null
jq -e '.attachments==[]' "$work/attachments.json" >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail run
request attach 'ATTACH IMAGE wrong TO VM test-vm'; must_fail run
printf 'changed\n' >> "$work/state/images/installer.iso"
request attach 'ATTACH IMAGE installer TO VM test-vm'; must_fail run
printf 'VM image attachment tests passed.\n'
