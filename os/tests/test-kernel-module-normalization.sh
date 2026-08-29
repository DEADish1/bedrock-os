#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
normalizer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/normalize-kernel-module-signature"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

printf 'deterministic module payload\n' > "$work/unsigned.ko"
cp "$work/unsigned.ko" "$work/signed.ko"
printf 'random-signature' >> "$work/signed.ko"
# Eight fixed module_signature bytes, then the 32-bit big-endian signature size (16).
printf '\000\000\002\000\000\000\000\000\000\000\000\020' >> "$work/signed.ko"
printf '~Module signature appended~\n' >> "$work/signed.ko"
xz --threads=1 --check=crc32 "$work/signed.ko"

"$normalizer" "$work/signed.ko.xz"
xz -dc "$work/signed.ko.xz" > "$work/result.ko"
cmp "$work/unsigned.ko" "$work/result.ko"
before=$(sha256sum "$work/signed.ko.xz" | awk '{print $1}')
"$normalizer" "$work/signed.ko.xz"
after=$(sha256sum "$work/signed.ko.xz" | awk '{print $1}')
[ "$before" = "$after" ] || { printf 'error: normalizing an unsigned module changed it\n' >&2; exit 1; }

printf 'Kernel module signature normalization tests passed.\n'
