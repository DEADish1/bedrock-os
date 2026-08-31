#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
planner="$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-passthrough-plan"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
jq -n '{schema:1,domains:[{name:"test-vm",vcpus:4,memory_mib:8192}]}' > "$work/domains.json"
jq -n '{schema:2,gpus:[{name:"card1",pci_address:"0000:03:00.0",vendor:"NVIDIA",vendor_id:"0x10de",device_id:"0x1234",driver:"nouveau",iommu_group:"17",iommu_group_devices:["0000:03:00.0","0000:03:00.1"],boot_vga:false,recognized_vendor:true},{name:"card0",pci_address:"0000:00:02.0",vendor:"Intel",vendor_id:"0x8086",device_id:"0x1111",driver:"i915",iommu_group:"1",iommu_group_devices:["0000:00:02.0"],boot_vga:true,recognized_vendor:true}],usb_devices:[{id:"1-2",vendor_id:"1234",product_id:"5678",device_class:"00",driver:"none",authorized:true,host_critical:false},{id:"1-1",vendor_id:"0000",product_id:"0000",device_class:"09",driver:"hub",authorized:true,host_critical:true}]}' > "$work/hardware.json"
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_HARDWARE="$work/hardware.json" BEDROCK_VM_DOMAINS="$work/domains.json" "$planner" "$work/request.json" "$work/plan.json"; }
jq -n '{schema:1,vm:"test-vm",kind:"gpu",devices:["0000:03:00.1","0000:03:00.0"],confirmation:"REVIEW GPU PASSTHROUGH VM test-vm DEVICES 0000:03:00.0,0000:03:00.1"}' > "$work/request.json"
run | jq -e '.status=="review-only" and .mutation_authorized==false and .iommu_group=="17" and (.warnings|length)==3' >/dev/null
jq -n '{schema:1,vm:"test-vm",kind:"usb",devices:["1-2"],confirmation:"REVIEW USB PASSTHROUGH VM test-vm DEVICES 1-2"}' > "$work/request.json"
run | jq -e '.kind=="usb" and .iommu_group==null' >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
jq -n '{schema:1,vm:"test-vm",kind:"gpu",devices:["0000:03:00.0"],confirmation:"REVIEW GPU PASSTHROUGH VM test-vm DEVICES 0000:03:00.0"}' > "$work/request.json"; must_fail run
jq -n '{schema:1,vm:"test-vm",kind:"gpu",devices:["0000:00:02.0"],confirmation:"REVIEW GPU PASSTHROUGH VM test-vm DEVICES 0000:00:02.0"}' > "$work/request.json"; must_fail run
jq -n '{schema:1,vm:"test-vm",kind:"usb",devices:["1-1"],confirmation:"REVIEW USB PASSTHROUGH VM test-vm DEVICES 1-1"}' > "$work/request.json"; must_fail run
printf 'VM passthrough planning tests passed.\n'
