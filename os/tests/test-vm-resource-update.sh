#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
updater="$ROOT/os/config/includes.chroot/usr/lib/bedrock/update-vm-resources"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state/definitions"
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
jq -n '{schema:2,cpu:{logical_processors:16},memory:{total_bytes:34359738368}}' > "$work/hardware.json"
cat > "$work/state/definitions/test-vm.xml" <<'EOF'
<domain><name>test-vm</name><memory>8192</memory><currentMemory>8192</currentMemory><vcpu>4</vcpu><os><boot dev='hd'/></os></domain>
EOF
cp "$work/state/definitions/test-vm.xml" "$work/runtime.xml"
printf 'shut off\n' > "$work/runtime-state"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
case "$3" in
  dominfo) exit 0 ;;
  domstate) cat "$BEDROCK_VM_RUNTIME_STATE" ;;
  dumpxml) cat "$BEDROCK_VM_RUNTIME_XML" ;;
  define) cp "$4" "$BEDROCK_VM_RUNTIME_XML" ;;
  *) exit 1 ;;
esac
EOF
cat > "$work/bin/xmlstarlet" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = sel ]; then
  eval "file=\${$#}"
  grep -o "boot dev='[^']*'" "$file" | sed "s/.*='//;s/'$//"
  exit 0
fi
case " $* " in
  *" -d /domain/os/boot "*) cat <<'XML'
<domain><name>test-vm</name><memory>12288</memory><currentMemory>12288</currentMemory><vcpu>6</vcpu><os></os></domain>
XML
    ;;
  *" -v cdrom "*) cat <<'XML'
<domain><name>test-vm</name><memory>12288</memory><currentMemory>12288</currentMemory><vcpu>6</vcpu><os><boot dev='cdrom'/><boot dev='hd'/></os></domain>
XML
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh" "$work/bin/xmlstarlet"
jq -n '{schema:1,name:"test-vm",vcpus:6,memory_mib:12288,boot_order:["cdrom","disk"],confirmation:"UPDATE VM test-vm CPU 6 MEMORY 12288 BOOT cdrom,disk"}' > "$work/request.json"
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_HARDWARE="$work/hardware.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_XMLSTARLET="$work/bin/xmlstarlet" BEDROCK_VM_RUNTIME_STATE="$work/runtime-state" BEDROCK_VM_RUNTIME_XML="$work/runtime.xml" "$updater" "$work/request.json"; }
run | jq -e '.status=="updated" and .vcpus==6 and .memory_mib==12288 and .boot_order==["cdrom","disk"]' >/dev/null
jq -e '.domains[0].vcpus==6 and .domains[0].memory_mib==12288' "$work/domains.json" >/dev/null
grep -q "<boot dev='cdrom'/>" "$work/state/definitions/test-vm.xml"
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
printf 'running\n' > "$work/runtime-state"; must_fail run; printf 'shut off\n' > "$work/runtime-state"
jq '.confirmation="UPDATE VM wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"; must_fail run
printf 'VM resource update tests passed.\n'
