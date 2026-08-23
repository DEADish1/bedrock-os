#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OS_DIR="$ROOT/os"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

for file in \
  "$OS_DIR/build.env" \
  "$OS_DIR/auto/config" \
  "$OS_DIR/config/package-lists/bedrock.list.chroot" \
  "$OS_DIR/config/includes.chroot/etc/bedrock-release"; do
  [ -s "$file" ] || fail "required file is missing or empty: $file"
done

(
  set -eu
  . "$OS_DIR/build.env"
  [ "$BEDROCK_DISTRIBUTION" = trixie ] || fail "distribution must remain pinned to trixie for 0.2"
  [ "$BEDROCK_ARCHITECTURE" = amd64 ] || fail "architecture must match the 1.0 support policy"
  case "$BEDROCK_VERSION" in 0.2.0-*) ;; *) fail "development image version must begin with 0.2.0-" ;; esac
)

if LC_ALL=C sort -c "$OS_DIR/config/package-lists/bedrock.list.chroot" 2>/dev/null; then :; else
  fail "package list must be sorted for stable review"
fi

duplicates=$(LC_ALL=C sort "$OS_DIR/config/package-lists/bedrock.list.chroot" | uniq -d)
[ -z "$duplicates" ] || fail "duplicate packages: $duplicates"

sh -n "$OS_DIR/auto/config"
sh -n "$OS_DIR/scripts/build-image.sh"
sh -n "$OS_DIR/scripts/verify-artifacts.sh"
sh -n "$OS_DIR/scripts/validate-layout.sh"
sh -n "$OS_DIR/scripts/build-uki.sh"
sh -n "$OS_DIR/scripts/validate-boot.sh"
sh -n "$OS_DIR/scripts/build-verified-root.sh"
sh -n "$OS_DIR/scripts/verify-verified-root.sh"
sh -n "$OS_DIR/scripts/assemble-disk-image.sh"
sh -n "$OS_DIR/scripts/verify-disk-image.sh"
sh -n "$OS_DIR/tests/test-uefi-boot.sh"
sh -n "$OS_DIR/tests/test-ab-rollback.sh"
sh -n "$OS_DIR/tests/test-update-bundle.sh"
sh -n "$OS_DIR/tests/test-update-install.sh"
sh -n "$OS_DIR/tests/test-hardware-inventory.sh"
sh -n "$OS_DIR/tests/test-reproducibility-check.sh"
sh -n "$OS_DIR/scripts/compare-reproducible-builds.sh"
sh -n "$OS_DIR/scripts/generate-development-keys.sh"
sh -n "$OS_DIR/scripts/build-raw-image.sh"
sh -n "$OS_DIR/scripts/build-installed-initrd.sh"
sh -n "$OS_DIR/scripts/create-update-bundle.sh"
sh -n "$OS_DIR/config/hooks/live/9999-bedrock-reproducible.hook.chroot"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/mark-boot-healthy"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/verify-update-bundle"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-update"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/collect-hardware-inventory"
grep -q '^ExecStart=/usr/lib/bedrock/mark-boot-healthy$' "$OS_DIR/config/includes.chroot/usr/lib/systemd/system/bedrock-boot-health.service"
[ -L "$OS_DIR/config/includes.chroot/etc/systemd/system/multi-user.target.wants/bedrock-boot-health.service" ] || { printf 'error: boot health service is not enabled\n' >&2; exit 1; }
[ -L "$OS_DIR/config/includes.chroot/etc/systemd/system/multi-user.target.wants/bedrock-hardware-inventory.service" ] || { printf 'error: hardware inventory service is not enabled\n' >&2; exit 1; }
"$OS_DIR/scripts/validate-layout.sh"
"$OS_DIR/scripts/validate-boot.sh"

printf 'Bedrock image configuration is valid.\n'
