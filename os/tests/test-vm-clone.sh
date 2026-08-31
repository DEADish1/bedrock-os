#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cloner="$ROOT/os/config/includes.chroot/usr/lib/bedrock/clone-vm"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,domains:[{name:"source-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
jq -n '{schema:2,cpu:{logical_processors:16},memory:{total_bytes:34359738368}}' > "$work/hardware.json"
jq -n '{schema:1,attachments:[]}' > "$work/images.json"; jq -n '{schema:1,attachments:[]}' > "$work/networks.json"
printf 'shut off\n' > "$work/runtime-state"; : > "$work/defined"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
case "$3" in
  dominfo) [ "$4" = source-vm ] || grep -Fxq "$4" "$BEDROCK_VM_DEFINED" ;;
  domstate) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  dumpxml) printf "<domain type='kvm'><name>%s</name></domain>\n" "$5" ;;
  undefine) sed -i "/^$4$/d" "$BEDROCK_VM_DEFINED" ;;
  *) exit 1 ;;
esac
EOF
cat > "$work/bin/virt-clone" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do case "$1" in --name) name=$2; shift 2;; --file) file=$2; shift 2;; *) shift;; esac; done
: > "$file"; printf '%s\n' "$name" >> "$BEDROCK_VM_DEFINED"
EOF
chmod +x "$work/bin/virsh" "$work/bin/virt-clone"
jq -n '{schema:1,source:"source-vm",name:"clone-vm",confirmation:"CLONE VM source-vm AS clone-vm"}' > "$work/request.json"
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_HARDWARE="$work/hardware.json" BEDROCK_VM_ATTACHMENTS="$work/images.json" BEDROCK_VM_NETWORK_ATTACHMENTS="$work/networks.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_VIRT_CLONE="$work/bin/virt-clone" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" BEDROCK_VM_DEFINED="$work/defined" "$cloner" "$work/request.json"; }
run | jq -e '.status=="cloned" and .running==false and .name=="clone-vm"' >/dev/null
jq -e '(.domains|length)==2 and any(.domains[];.name=="clone-vm")' "$work/domains.json" >/dev/null
[ -f "$work/state/disks/clone-vm.qcow2" ]
grep -q '<name>clone-vm</name>' "$work/state/definitions/clone-vm.xml"
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail run
printf 'VM clone tests passed.\n'
