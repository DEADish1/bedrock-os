#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
registrar="$ROOT/os/config/includes.chroot/usr/lib/bedrock/register-vm"
renderer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/render-vm-domain"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state/disks"
cp "$renderer" "$work/render-vm-domain"
sed "s|/usr/lib/bedrock/render-vm-domain|$work/render-vm-domain|" "$registrar" > "$work/register-vm"
chmod +x "$work/register-vm" "$work/render-vm-domain"
cat > "$work/bin/qemu-img" <<'EOF'
#!/bin/sh
set -eu
[ "$1 $2 $3" = "create -f qcow2" ]
shift 5
: > "$1"
EOF
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$BEDROCK_VM_TEST_LOG"
[ "${BEDROCK_VM_FAIL_DEFINE:-0}" != 1 ] || case " $* " in *" define "*) exit 1;; esac
case " $* " in *" dominfo "*) exit 1;; esac
EOF
chmod +x "$work/bin/qemu-img" "$work/bin/virsh"
jq -n '{schema:1,status:"review-only",mutation_authorized:false,name:"test-vm",vcpus:4,memory_mib:8192,disk_size_gib:64,firmware:"uefi",network:"default",autostart:true,confirmation_phrase:"CREATE VM test-vm",reservation:{host_cpus:16,used_vcpus:4,bedrock_reserved_cpus:2,host_memory_mib:32768,used_memory_mib:4096,bedrock_reserved_memory_mib:2048}}' > "$work/plan.json"
BEDROCK_VM_TEST_MODE=1 "$work/render-vm-domain" "$work/plan.json" "$work/domain.xml" >/dev/null
plan_hash=$(sha256sum "$work/plan.json" | awk '{print $1}')
definition_hash=$(sha256sum "$work/domain.xml" | awk '{print $1}')
jq -n --arg plan "$plan_hash" --arg definition "$definition_hash" '{schema:1,action:"create",name:"test-vm",confirmation:"CREATE VM test-vm",plan_sha256:$plan,definition_sha256:$definition}' > "$work/auth.json"
jq -n '{schema:1,domains:[]}' > "$work/domains.json"
: > "$work/virsh.log"
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_QEMU_IMG="$work/bin/qemu-img" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_TEST_LOG="$work/virsh.log" "$work/register-vm" "$work/plan.json" "$work/domain.xml" "$work/auth.json"; }
run | jq -e '.status=="registered" and .running==false' >/dev/null
[ -f "$work/state/disks/test-vm.qcow2" ]
jq -e '.domains==[{memory_mib:8192,name:"test-vm",vcpus:4}]' "$work/domains.json" >/dev/null
grep -q 'define .*domain.xml' "$work/virsh.log"
grep -q 'autostart test-vm' "$work/virsh.log"
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
rm -f "$work/state/disks/test-vm.qcow2"; jq -n '{schema:1,domains:[]}' > "$work/domains.json"
jq '.confirmation="CREATE VM other"' "$work/auth.json" > "$work/bad-auth.json"
must_fail env BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_QEMU_IMG="$work/bin/qemu-img" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_TEST_LOG="$work/virsh.log" "$work/register-vm" "$work/plan.json" "$work/domain.xml" "$work/bad-auth.json"
BEDROCK_VM_FAIL_DEFINE=1 must_fail run
[ ! -e "$work/state/disks/test-vm.qcow2" ]
jq -e '.domains==[]' "$work/domains.json" >/dev/null
printf 'VM registration tests passed.\n'
