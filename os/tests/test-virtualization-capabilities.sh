#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
collector="$ROOT/os/config/includes.chroot/usr/lib/bedrock/collect-virtualization-capabilities"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/root/proc" "$work/root/dev" "$work/bin" "$work/firmware" "$work/state"
printf 'flags : fpu svm sse4_2\n' > "$work/root/proc/cpuinfo"
: > "$work/root/dev/kvm"
printf '#!/bin/sh\nexit 0\n' > "$work/bin/qemu-system-x86_64"
printf '#!/bin/sh\nexit 0\n' > "$work/bin/swtpm"
chmod 0755 "$work/bin/qemu-system-x86_64" "$work/bin/swtpm"
printf firmware > "$work/firmware/OVMF_CODE_4M.secboot.fd"

run_collector() {
  BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_TEST_ROOT="$work/root" \
    BEDROCK_VM_OUTPUT="$work/state/capabilities.json" BEDROCK_VM_QEMU="${BEDROCK_VM_QEMU_OVERRIDE:-$work/bin/qemu-system-x86_64}" \
    BEDROCK_VM_OVMF="$work/firmware/OVMF_CODE_4M.secboot.fd" BEDROCK_VM_SWTPM="$work/bin/swtpm" \
    BEDROCK_VM_VIRSH_OK="${1:-1}" "$collector"
}
run_collector 1 | jq -e '.schema==1 and .supported==true and .accelerator.cpu_virtualization==true and .accelerator.kvm_device==true and .qemu==true and .ovmf==true and .tpm2_emulator==true and .libvirt_system==true and .reasons==[]' >/dev/null

mv "$work/bin/swtpm" "$work/bin/swtpm-missing"
run_collector 1 | jq -e '.supported==false and .tpm2_emulator==false and .reasons==["swtpm-unavailable"]' >/dev/null
mv "$work/bin/swtpm-missing" "$work/bin/swtpm"

rm "$work/root/dev/kvm"
run_collector 1 | jq -e '.supported==false and .reasons==["kvm-device-unavailable"]' >/dev/null
: > "$work/root/dev/kvm"
run_collector 0 | jq -e '.supported==false and .reasons==["libvirt-system-unavailable"]' >/dev/null
printf 'flags : fpu sse4_2\n' > "$work/root/proc/cpuinfo"
run_collector 0 | jq -e '.supported==false and .reasons==["cpu-virtualization-unavailable","libvirt-system-unavailable"]' >/dev/null

ln -s "$work/bin/qemu-system-x86_64" "$work/bin/indirect-qemu"
if [ -L "$work/bin/indirect-qemu" ]; then
  BEDROCK_VM_QEMU_OVERRIDE="$work/bin/indirect-qemu" run_collector 1 | jq -e '.supported==false and (.reasons|index("qemu-unavailable")!=null)' >/dev/null
fi
printf 'Virtualization capability tests passed.\n'
