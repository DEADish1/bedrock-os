#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OS_DIR="$ROOT/os"

usage() {
  printf 'usage: %s SLOT ROOT_HASH KERNEL INITRD OUTPUT\n' "$0" >&2
  exit 2
}

[ "$#" -eq 6 ] || usage
slot=$1
root_hash=$2
kernel=$3
initrd=$4
output=$5
os_release=$6

case "$slot" in
  a)
    root_partuuid=20000000-0000-4000-8000-000000000002
    verity_partuuid=20000000-0000-4000-8000-000000000003
    image_version=2
    ;;
  b)
    root_partuuid=20000000-0000-4000-8000-000000000005
    verity_partuuid=20000000-0000-4000-8000-000000000006
    image_version=1
    ;;
  *) printf 'error: slot must be a or b\n' >&2; exit 2 ;;
esac
image_version=${BEDROCK_IMAGE_VERSION:-$image_version}
printf '%s' "$image_version" | grep -Eq '^[1-9][0-9]*$' || { printf 'error: BEDROCK_IMAGE_VERSION must be a positive integer\n' >&2; exit 2; }
printf '%s' "$root_hash" | grep -Eq '^[0-9a-fA-F]{64,128}$' || { printf 'error: invalid dm-verity root hash\n' >&2; exit 2; }
[ -s "$kernel" ] && [ -s "$initrd" ] && [ -s "$os_release" ] || { printf 'error: kernel, initrd, or os-release is missing\n' >&2; exit 1; }
: "${BEDROCK_SECURE_BOOT_KEY:?set BEDROCK_SECURE_BOOT_KEY to a protected signing key}"
: "${BEDROCK_SECURE_BOOT_CERT:?set BEDROCK_SECURE_BOOT_CERT to its certificate}"
[ -s "$BEDROCK_SECURE_BOOT_KEY" ] && [ -s "$BEDROCK_SECURE_BOOT_CERT" ] || { printf 'error: signing material is missing\n' >&2; exit 1; }
command -v ukify >/dev/null 2>&1 || { printf 'error: systemd-ukify is required\n' >&2; exit 1; }

uki_os_release=$(mktemp)
cleanup() { rm -f "$uki_os_release"; }
trap cleanup EXIT INT TERM
sed '/^IMAGE_VERSION=/d' "$os_release" > "$uki_os_release"
printf 'IMAGE_VERSION=%s\n' "$image_version" >> "$uki_os_release"

base_cmdline=$(tr '\n' ' ' < "$OS_DIR/boot/bedrock-cmdline" | sed 's/[[:space:]]*$//')
cmdline="$base_cmdline roothash=$root_hash systemd.verity_root_data=PARTUUID=$root_partuuid systemd.verity_root_hash=PARTUUID=$verity_partuuid bedrock.slot=$slot"

mkdir -p "$(dirname -- "$output")"
ukify build \
  --linux="$kernel" \
  --initrd="$initrd" \
  --os-release="@$uki_os_release" \
  --cmdline="$cmdline" \
  --secureboot-private-key="$BEDROCK_SECURE_BOOT_KEY" \
  --secureboot-certificate="$BEDROCK_SECURE_BOOT_CERT" \
  --output="$output"

printf 'Built signed Bedrock slot %s UKI: %s\n' "$slot" "$output"
