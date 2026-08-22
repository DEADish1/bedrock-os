#!/bin/sh
set -eu

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { printf 'usage: %s IMAGE.raw [FAILED_SLOT]\n' "$0" >&2; exit 2; }
image=$1
failed_slot=${2:-a}
case "$failed_slot" in a) healthy_slot=b; root_number=2 ;; b) healthy_slot=a; root_number=5 ;; *) printf 'error: failed slot must be a or b\n' >&2; exit 2 ;; esac
[ -s "$image" ] || { printf 'error: VM image is missing\n' >&2; exit 1; }
for tool in qemu-system-x86_64 sgdisk mdir mren; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }
done

ovmf_code=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
[ -r "$ovmf_code" ] && [ -r "$ovmf_vars_template" ] || { printf 'error: OVMF firmware is unavailable\n' >&2; exit 1; }

work=$(mktemp -d)
test_image="$work/bedrock-rollback.raw"
vars="$work/OVMF_VARS.fd"
cp --reflink=auto --sparse=always "$image" "$test_image"
cp "$ovmf_vars_template" "$vars"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM

# Unless the caller already installed a broken image, damage the failed slot
# after its UKI has been signed with the original dm-verity root hash.
if [ "${BEDROCK_SKIP_FAILURE_INJECTION:-0}" != 1 ]; then
  root_sector=$(sgdisk --info="$root_number" "$test_image" | sed -n 's/^First sector: *\([0-9][0-9]*\).*/\1/p')
  [ -n "$root_sector" ] || { printf 'error: could not locate failed slot %s\n' "$failed_slot" >&2; exit 1; }
  dd if=/dev/zero of="$test_image" bs=1 seek=$((root_sector * 512 + 1024)) count=4096 conv=notrunc status=none
fi

esp_offset=$((2048 * 512))
entry_present() {
  mdir -b -i "$test_image@@$esp_offset" ::/EFI/Linux/ 2>/dev/null | grep -F "$1" >/dev/null
}
# A prior smoke test may have promoted A on the source artifact. Re-arm only the
# disposable copy so this test always begins at the factory three-attempt state.
if entry_present "bedrock-$failed_slot.efi"; then
  mren -i "$test_image@@$esp_offset" "::/EFI/Linux/bedrock-$failed_slot.efi" "::/EFI/Linux/bedrock-$failed_slot+3.efi"
fi

boot_once() {
  attempt=$1
  expected=$2
  log="$work/serial-$attempt.log"
  qemu-system-x86_64 \
    -machine q35,accel=tcg -cpu max -smp 2 -m 2048 \
    -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code" \
    -drive "if=pflash,format=raw,file=$vars" \
    -drive "if=virtio,format=raw,readonly=off,file=$test_image" \
    -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
    -display none -monitor none -serial "file:$log" -no-reboot &
  qemu_pid=$!
  elapsed=0
  if [ "$expected" = failed ]; then limit=70; else limit=90; fi
  while [ "$elapsed" -lt "$limit" ]; do
    if [ "$expected" = healthy ] && grep -F "BEDROCK_BOOT_HEALTHY slot=$healthy_slot" "$log" >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then break; fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  kill "$qemu_pid" 2>/dev/null || true
  wait "$qemu_pid" 2>/dev/null || true

  if [ "$expected" = failed ]; then
    if grep -F 'BEDROCK_BOOT_HEALTHY slot=' "$log" >/dev/null 2>&1; then
      printf 'error: failed slot %s attempt %s unexpectedly became healthy\n' "$failed_slot" "$attempt" >&2
      tail -n 80 "$log" >&2 || true
      exit 1
    fi
  elif ! grep -F "BEDROCK_BOOT_HEALTHY slot=$healthy_slot" "$log" >/dev/null 2>&1; then
    printf 'error: slot %s did not become healthy after rollback\n' "$healthy_slot" >&2
    tail -n 80 "$log" >&2 || true
    exit 1
  fi
}

entry_present "bedrock-$failed_slot+3.efi" || { printf 'error: initial slot %s boot count is not three\n' "$failed_slot" >&2; exit 1; }
for attempt in 1 2 3; do
  boot_once "$attempt" failed
  remaining=$((3 - attempt))
  entry_present "bedrock-$failed_slot+$remaining-$attempt.efi" || {
    printf 'error: slot %s boot count did not advance after attempt %s\n' "$failed_slot" "$attempt" >&2
    mdir -b -i "$test_image@@$esp_offset" ::/EFI/Linux/ >&2 || true
    exit 1
  }
done

boot_once 4 healthy
entry_present "bedrock-$healthy_slot.efi" || { printf 'error: healthy slot %s was not promoted\n' "$healthy_slot" >&2; exit 1; }
printf 'Bedrock rolled back from failed slot %s to healthy slot %s after three attempts.\n' "$failed_slot" "$healthy_slot"
