#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OS_DIR="$ROOT/os"
OUT_DIR="$OS_DIR/out"
ROOTFS="$OS_DIR/chroot"
[ "$(id -u)" -eq 0 ] || { printf 'error: raw image build requires root on Linux\n' >&2; exit 1; }
[ -d "$ROOTFS" ] || { printf 'error: live-build root filesystem is unavailable\n' >&2; exit 1; }

if [ -z "${BEDROCK_VERITY_KEY:-}" ] || [ -z "${BEDROCK_VERITY_CERT:-}" ] || [ -z "${BEDROCK_SECURE_BOOT_KEY:-}" ] || [ -z "${BEDROCK_SECURE_BOOT_CERT:-}" ]; then
  [ "${BEDROCK_ALLOW_EPHEMERAL_KEYS:-0}" = 1 ] || { printf 'error: protected release signing keys are required\n' >&2; exit 1; }
  key_dir=$(mktemp -d)
  trap 'rm -rf "$key_dir"' EXIT INT TERM
  "$OS_DIR/scripts/generate-development-keys.sh" "$key_dir" >/dev/null
  BEDROCK_VERITY_KEY="$key_dir/DO-NOT-SHIP-development.key"
  BEDROCK_VERITY_CERT="$key_dir/DO-NOT-SHIP-development.crt"
  BEDROCK_SECURE_BOOT_KEY=$BEDROCK_VERITY_KEY
  BEDROCK_SECURE_BOOT_CERT=$BEDROCK_VERITY_CERT
  BEDROCK_UPDATE_CERT=$BEDROCK_VERITY_CERT
  export BEDROCK_VERITY_KEY BEDROCK_VERITY_CERT BEDROCK_SECURE_BOOT_KEY BEDROCK_SECURE_BOOT_CERT BEDROCK_UPDATE_CERT
  signing_mode=development-ephemeral
else
  : "${BEDROCK_UPDATE_CERT:?set BEDROCK_UPDATE_CERT to the trusted release update certificate}"
  [ -s "$BEDROCK_UPDATE_CERT" ] || { printf 'error: update trust certificate is missing\n' >&2; exit 1; }
  signing_mode=release-protected
fi

kernel=$(find "$ROOTFS/boot" -maxdepth 1 -name 'vmlinuz-*' -type f | LC_ALL=C sort | tail -n1)
kernel_version=$(basename "$kernel" | sed 's/^vmlinuz-//')
initrd=$("$OS_DIR/scripts/build-installed-initrd.sh" "$ROOTFS" "$kernel_version" | tail -n1)
os_release="$ROOTFS/etc/os-release"
boot_binary="$ROOTFS/usr/lib/systemd/boot/efi/systemd-bootx64.efi"
for file in "$kernel" "$initrd" "$os_release" "$boot_binary"; do
  [ -s "$file" ] || { printf 'error: required boot component is missing: %s\n' "$file" >&2; exit 1; }
done

components="$OUT_DIR/components"
mkdir -p "$components"
mkdir -p "$ROOTFS/usr/share/bedrock"
"$ROOTFS/usr/lib/bedrock/validate-update-trust" "$BEDROCK_UPDATE_CERT"
cp "$BEDROCK_UPDATE_CERT" "$ROOTFS/usr/share/bedrock/update-trust.pem"
"$OS_DIR/scripts/build-verified-root.sh" "$ROOTFS" a "$components"
"$OS_DIR/scripts/build-verified-root.sh" "$ROOTFS" b "$components"
"$OS_DIR/scripts/build-uki.sh" a "$(cat "$components/bedrock-root-a.roothash")" "$kernel" "$initrd" "$components/bedrock-a.efi" "$os_release"
"$OS_DIR/scripts/build-uki.sh" b "$(cat "$components/bedrock-root-b.roothash")" "$kernel" "$initrd" "$components/bedrock-b.efi" "$os_release"
cp "$boot_binary" "$components/systemd-bootx64.efi"

raw="$OUT_DIR/bedrock-os-amd64.raw"
"$OS_DIR/scripts/assemble-disk-image.sh" "$components" "$raw"
jq -n --arg mode "$signing_mode" '{schema:1,signing_mode:$mode,release_eligible:($mode == "release-protected")}' > "$OUT_DIR/bedrock-signing-manifest.json"
printf 'Built Bedrock raw image with %s signing.\n' "$signing_mode"
