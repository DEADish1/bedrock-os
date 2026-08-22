#!/bin/sh
set -eu

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { printf 'usage: %s IMAGE.raw [EXPECTED_SLOT]\n' "$0" >&2; exit 2; }
image=$1
expected_slot=${2:-a}
case "$expected_slot" in a|b) ;; *) printf 'error: expected slot must be a or b\n' >&2; exit 2 ;; esac
[ -s "$image" ] || { printf 'error: VM image is missing\n' >&2; exit 1; }
for tool in qemu-system-x86_64; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }
done

ovmf_code=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
[ -r "$ovmf_code" ] && [ -r "$ovmf_vars_template" ] || { printf 'error: OVMF firmware is unavailable\n' >&2; exit 1; }

work=$(mktemp -d)
log="$work/serial.log"
vars="$work/OVMF_VARS.fd"
test_image="$work/bedrock-test.raw"
cp "$ovmf_vars_template" "$vars"
if [ "${BEDROCK_TEST_IN_PLACE:-0}" = 1 ]; then
  [ "${BEDROCK_TEST_MODE:-0}" = 1 ] || { printf 'error: in-place boot is test-only\n' >&2; exit 1; }
  test_image=$image
else
  cp --reflink=auto --sparse=always "$image" "$test_image"
fi
cleanup() { rm -f "$vars" "$log"; [ "${BEDROCK_TEST_IN_PLACE:-0}" = 1 ] || rm -f "$test_image"; rmdir "$work" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

qemu-system-x86_64 \
  -machine q35,accel=tcg -cpu max -smp 2 -m 2048 \
  -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code" \
  -drive "if=pflash,format=raw,file=$vars" \
  -drive "if=virtio,format=raw,readonly=off,file=$test_image" \
  -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
  -display none -monitor none -serial "file:$log" -no-reboot &
qemu_pid=$!
status=124
elapsed=0
while [ "$elapsed" -lt 180 ]; do
  if grep -F "BEDROCK_BOOT_HEALTHY slot=$expected_slot" "$log" >/dev/null 2>&1; then
    status=0
    break
  fi
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    set +e
    wait "$qemu_pid"
    status=$?
    set -e
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
kill "$qemu_pid" 2>/dev/null || true
wait "$qemu_pid" 2>/dev/null || true

if ! grep -F "BEDROCK_BOOT_HEALTHY slot=$expected_slot" "$log" >/dev/null; then
  printf 'error: Bedrock did not report a healthy slot %s boot (QEMU status %s)\n' "$expected_slot" "$status" >&2
  tail -n 80 "$log" >&2 || true
  exit 1
fi

printf 'Bedrock UEFI VM boot reached healthy slot %s.\n' "$expected_slot"
