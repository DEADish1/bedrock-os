#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
planner="$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-vm-plan"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/out"
jq -n '{schema:2,cpu:{logical_processors:16},memory:{total_bytes:34359738368}}' > "$work/hardware.json"
jq -n '{schema:1,supported:true,accelerator:{cpu_virtualization:true,kvm_device:true},qemu:true,ovmf:true,libvirt_system:true,reasons:[]}' > "$work/capabilities.json"
jq -n '{schema:1,domains:[{name:"existing-vm",vcpus:4,memory_mib:4096}]}' > "$work/domains.json"
jq -n '{schema:1,name:"new-vm",vcpus:4,memory_mib:8192,disk_size_gib:64,firmware:"uefi",network:"default",autostart:false}' > "$work/request.json"

run_planner() {
  BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_HARDWARE="$work/hardware.json" \
    BEDROCK_VM_CAPABILITIES="$work/capabilities.json" BEDROCK_VM_DOMAINS="$work/domains.json" \
    "$planner" "$work/request.json" "$work/out/plan.json"
}
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded: %s\n' "$*" >&2; exit 1; fi; }

run_planner | jq -e '.status=="review-only" and .mutation_authorized==false and .name=="new-vm" and .confirmation_phrase=="CREATE VM new-vm" and .reservation.bedrock_reserved_cpus==2 and .reservation.bedrock_reserved_memory_mib==2048' >/dev/null
jq '.vcpus=11' "$work/request.json" > "$work/request.tmp" && mv "$work/request.tmp" "$work/request.json"
must_fail run_planner
jq '.vcpus=4 | .memory_mib=28672' "$work/request.json" > "$work/request.tmp" && mv "$work/request.tmp" "$work/request.json"
must_fail run_planner
jq '.memory_mib=8192 | .name="existing-vm"' "$work/request.json" > "$work/request.tmp" && mv "$work/request.tmp" "$work/request.json"
must_fail run_planner
jq '.name="Bad Name"' "$work/request.json" > "$work/request.tmp" && mv "$work/request.tmp" "$work/request.json"
must_fail run_planner
jq '.name="new-vm"' "$work/request.json" > "$work/request.tmp" && mv "$work/request.tmp" "$work/request.json"
jq '.supported=false | .reasons=["kvm-device-unavailable"]' "$work/capabilities.json" > "$work/capabilities.tmp" && mv "$work/capabilities.tmp" "$work/capabilities.json"
must_fail run_planner
printf 'VM creation planning tests passed.\n'
