#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
renderer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/render-vm-domain"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
jq -n '{schema:1,status:"review-only",mutation_authorized:false,name:"test-vm",vcpus:4,memory_mib:8192,disk_size_gib:64,firmware:"uefi",network:"default",autostart:false,confirmation_phrase:"CREATE VM test-vm",reservation:{host_cpus:16,used_vcpus:4,bedrock_reserved_cpus:2,host_memory_mib:32768,used_memory_mib:4096,bedrock_reserved_memory_mib:2048}}' > "$work/plan.json"

BEDROCK_VM_TEST_MODE=1 "$renderer" "$work/plan.json" "$work/domain-a.xml" >/dev/null
BEDROCK_VM_TEST_MODE=1 "$renderer" "$work/plan.json" "$work/domain-b.xml" >/dev/null
cmp "$work/domain-a.xml" "$work/domain-b.xml"
grep -q "<domain type='kvm'>" "$work/domain-a.xml"
grep -q "<type arch='x86_64' machine='q35'>hvm</type>" "$work/domain-a.xml"
grep -q "<loader readonly='yes' secure='yes' type='pflash'>/usr/share/OVMF/OVMF_CODE_4M.secboot.fd</loader>" "$work/domain-a.xml"
grep -q "template='/usr/share/OVMF/OVMF_VARS_4M.ms.fd'" "$work/domain-a.xml"
grep -q "source file='/var/lib/bedrock/virtualization/disks/test-vm.qcow2'" "$work/domain-a.xml"
grep -q "<source network='default'/>" "$work/domain-a.xml"
grep -q "<cpu mode='host-passthrough' check='none' migratable='off'/>" "$work/domain-a.xml"
grep -q "<tpm model='tpm-crb'><backend type='emulator' version='2.0' persistent_state='yes'/></tpm>" "$work/domain-a.xml"
grep -q "<channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>" "$work/domain-a.xml"
grep -q "<graphics type='vnc' autoport='no' socket='/run/libvirt/qemu/bedrock-test-vm.vnc' sharePolicy='ignore'/>" "$work/domain-a.xml"
! grep -Eq "graphics[^>]+[[:space:]](port|listen)=|type='spice'" "$work/domain-a.xml"
! grep -Eq 'qemu:commandline|hostdev|filesystem|script|interface type=.bridge' "$work/domain-a.xml"

must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded: %s\n' "$*" >&2; exit 1; fi; }
jq '.mutation_authorized=true' "$work/plan.json" > "$work/bad.json"
must_fail env BEDROCK_VM_TEST_MODE=1 "$renderer" "$work/bad.json" "$work/bad.xml"
jq '.reservation.host_cpus=9' "$work/plan.json" > "$work/bad.json"
must_fail env BEDROCK_VM_TEST_MODE=1 "$renderer" "$work/bad.json" "$work/bad.xml"
jq '.name="bad<name"' "$work/plan.json" > "$work/bad.json"
must_fail env BEDROCK_VM_TEST_MODE=1 "$renderer" "$work/bad.json" "$work/bad.xml"
jq '.unexpected="field"' "$work/plan.json" > "$work/bad.json"
must_fail env BEDROCK_VM_TEST_MODE=1 "$renderer" "$work/bad.json" "$work/bad.xml"

printf 'VM domain rendering tests passed.\n'
