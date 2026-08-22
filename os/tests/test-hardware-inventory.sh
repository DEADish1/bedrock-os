#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$ROOT/os/tests/fixtures/hardware"
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
mkdir -p "$work/sys/class/drm"
PATH="$fixture/bin:$PATH" BEDROCK_PROC_ROOT="$fixture/proc" BEDROCK_SYS_ROOT="$work/sys" \
  "$ROOT/os/config/includes.chroot/usr/lib/bedrock/collect-hardware-inventory" "$work/inventory.json"
jq -e '
  .schema == 2 and .cpu.architecture == "x86_64" and .cpu.logical_processors == 8 and
  .cpu.virtualization_supported == true and .memory.total_bytes == 16777216000 and
  (.disks | length == 1) and .disks[0].model == "Bedrock SSD" and
  (.storage_controllers | length == 2) and
  .storage_controllers[0].class == "hardware-raid" and .storage_controllers[1].class == "sata" and
  (.networks | length == 1) and .networks[0].name == "enp1s0" and (.gpus | type == "array")
' "$work/inventory.json" >/dev/null
printf 'Bedrock hardware inventory schema and discovery output are valid.\n'
