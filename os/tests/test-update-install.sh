#!/bin/sh
set -eu

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { printf 'usage: %s IMAGE.raw COMPONENT_DIR [good|bad]\n' "$0" >&2; exit 2; }
image=$1
components=$2
mode=${3:-good}
case "$mode" in good|bad) ;; *) printf 'error: mode must be good or bad\n' >&2; exit 2 ;; esac
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
for tool in mdir mcopy sgdisk; do command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }; done

work=$(mktemp -d)
cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT INT TERM
test_image="$work/update-test.raw"
cp --reflink=auto --sparse=always "$image" "$test_image"
mkdir -p "$work/artifacts" "$work/bundle" "$work/keys" "$work/state"
cp "$components/bedrock-root-b.erofs" "$work/artifacts/root.erofs"
cp "$components/bedrock-root-b.verity" "$work/artifacts/root.verity"
cp "$components/bedrock-root-b.verity-sig.json" "$work/artifacts/verity-sig.json"
if [ "$mode" = bad ]; then
  dd if=/dev/zero of="$work/artifacts/root.erofs" bs=1 seek=1024 count=4096 conv=notrunc status=none
fi

BEDROCK_ALLOW_EPHEMERAL_KEYS=1 "$ROOT/os/scripts/generate-development-keys.sh" "$work/keys" >/dev/null
key="$work/keys/DO-NOT-SHIP-development.key"
cert="$work/keys/DO-NOT-SHIP-development.crt"
kernel=$(find "$ROOT/os/chroot/boot" -maxdepth 1 -name 'vmlinuz-*' -type f | LC_ALL=C sort | tail -n1)
initrd=$(find "$ROOT/os/chroot/boot" -maxdepth 1 -name 'initrd.img-bedrock-*' -type f | LC_ALL=C sort | tail -n1)
BEDROCK_IMAGE_VERSION=3 BEDROCK_SECURE_BOOT_KEY="$key" BEDROCK_SECURE_BOOT_CERT="$cert" \
  "$ROOT/os/scripts/build-uki.sh" b "$(cat "$components/bedrock-root-b.roothash")" "$kernel" "$initrd" "$work/artifacts/uki.efi" "$ROOT/os/chroot/etc/os-release" >/dev/null
BEDROCK_UPDATE_KEY="$key" BEDROCK_UPDATE_CERT="$cert" \
  "$ROOT/os/scripts/create-update-bundle.sh" 0.2.0-test 3 "$work/artifacts" "$work/bundle" >/dev/null

BEDROCK_TEST_MODE=1 BEDROCK_CURRENT_SLOT=a BEDROCK_DISK_IMAGE="$test_image" \
  BEDROCK_UPDATE_STATE_DIR="$work/state/lib/bedrock/update" \
  BEDROCK_VERIFY_UPDATE="$ROOT/os/config/includes.chroot/usr/lib/bedrock/verify-update-bundle" BEDROCK_UPDATE_CERT="$cert" \
  "$ROOT/os/config/includes.chroot/usr/sbin/bedrock-update" "$work/bundle" >/dev/null
mdir -b -i "$test_image@@1048576" ::/EFI/Linux/ | grep -F 'bedrock-b+3.efi' >/dev/null || { printf 'error: update UKI was not armed\n' >&2; exit 1; }
if [ "$mode" = good ]; then
  BEDROCK_TEST_MODE=1 BEDROCK_TEST_IN_PLACE=1 "$ROOT/os/tests/test-uefi-boot.sh" "$test_image" b
  printf 'Bedrock installed signed generation 3 into inactive B and booted it healthy.\n'
else
  BEDROCK_SKIP_FAILURE_INJECTION=1 "$ROOT/os/tests/test-ab-rollback.sh" "$test_image" b
  printf 'Bedrock installed a signed bad generation into B and rolled back to healthy A.\n'
fi
