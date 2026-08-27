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
sh -n "$OS_DIR/scripts/verify-live-installer-package.sh"
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
sh -n "$OS_DIR/tests/test-update-preferences.sh"
sh -n "$OS_DIR/tests/test-hardware-inventory.sh"
sh -n "$OS_DIR/tests/test-storage-health.sh"
sh -n "$OS_DIR/tests/test-storage-alerts.sh"
sh -n "$OS_DIR/tests/test-storage-plan.sh"
sh -n "$OS_DIR/tests/test-storage-operations.sh"
sh -n "$OS_DIR/tests/test-nas-management.sh"
sh -n "$OS_DIR/tests/test-storage-recovery.sh"
sh -n "$OS_DIR/tests/test-storage-activation.sh"
sh -n "$OS_DIR/tests/test-real-storage-linux.sh"
sh -n "$OS_DIR/tests/test-guided-storage.sh"
sh -n "$OS_DIR/tests/test-first-run-config.sh"
sh -n "$OS_DIR/tests/test-guided-install.sh"
sh -n "$OS_DIR/tests/test-install-acceptance-report.sh"
sh -n "$OS_DIR/tests/validate-install-acceptance-report.sh"
sh -n "$OS_DIR/tests/test-acceptance-workspace.sh"
sh -n "$OS_DIR/tests/test-0.2-0.3-acceptance.sh"
sh -n "$OS_DIR/tests/validate-0.2-0.3-acceptance.sh"
sh -n "$OS_DIR/tests/test-reproducibility-check.sh"
sh -n "$OS_DIR/tests/validate-boot-test-report.sh"
sh -n "$OS_DIR/tests/test-boot-test-report.sh"
sh -n "$OS_DIR/tests/test-boot-acceptance-capture.sh"
sh -n "$OS_DIR/scripts/compare-reproducible-builds.sh"
sh -n "$OS_DIR/scripts/generate-development-keys.sh"
sh -n "$OS_DIR/scripts/build-raw-image.sh"
sh -n "$OS_DIR/scripts/build-installed-initrd.sh"
sh -n "$OS_DIR/scripts/create-update-bundle.sh"
sh -n "$OS_DIR/installer/validate-install-target.sh"
sh -n "$OS_DIR/installer/create-install-plan.sh"
sh -n "$OS_DIR/installer/simulate-install-image.sh"
sh -n "$OS_DIR/installer/create-protected-install-request.sh"
sh -n "$OS_DIR/installer/preflight-protected-install.sh"
sh -n "$OS_DIR/installer/build-protected-system-writer.sh"
sh -n "$OS_DIR/installer/write-protected-install.sh"
sh -n "$OS_DIR/installer/finalize-protected-layout.sh"
sh -n "$OS_DIR/installer/stage-protected-installer.sh"
sh -n "$OS_DIR/installer/bedrock-install-guided.sh"
sh -n "$OS_DIR/tests/test-protected-loop-install.sh"
sh -n "$OS_DIR/tests/test-protected-installer-package.sh"
sh -n "$OS_DIR/config/hooks/live/9999-bedrock-reproducible.hook.chroot"
grep -q '^Dir::Cache::pkgcache "";$' "$OS_DIR/config/includes.chroot/etc/apt/apt.conf.d/99bedrock-reproducible"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/mark-boot-healthy"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/verify-update-bundle"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-update"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/check-for-updates"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-update-settings"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-setup-updates"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/collect-hardware-inventory"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/collect-storage-health"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/process-storage-alerts"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/create-storage-plan"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-storage"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-storage-guided"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-boot-acceptance"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-nas"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/storage-integrity"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/mount-storage-resources"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/render-nas-services"
sh -n "$OS_DIR/config/includes.chroot/usr/lib/bedrock/validate-first-run-config"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-first-run"
sh -n "$OS_DIR/config/includes.chroot/usr/sbin/bedrock-apply-first-run"
grep -q '^ExecStart=/usr/lib/bedrock/mark-boot-healthy$' "$OS_DIR/config/includes.chroot/usr/lib/systemd/system/bedrock-boot-health.service"
[ -L "$OS_DIR/config/includes.chroot/etc/systemd/system/multi-user.target.wants/bedrock-boot-health.service" ] || { printf 'error: boot health service is not enabled\n' >&2; exit 1; }
[ -L "$OS_DIR/config/includes.chroot/etc/systemd/system/multi-user.target.wants/bedrock-hardware-inventory.service" ] || { printf 'error: hardware inventory service is not enabled\n' >&2; exit 1; }
[ -L "$OS_DIR/config/includes.chroot/etc/systemd/system/timers.target.wants/bedrock-update-check.timer" ] || { printf 'error: update-check timer is not enabled\n' >&2; exit 1; }
[ -L "$OS_DIR/config/includes.chroot/etc/systemd/system/timers.target.wants/bedrock-storage-health.timer" ] || { printf 'error: storage-health timer is not enabled\n' >&2; exit 1; }
[ -L "$OS_DIR/config/includes.chroot/etc/systemd/system/multi-user.target.wants/bedrock-storage-activation.service" ] || { printf 'error: storage activation service is not enabled\n' >&2; exit 1; }
[ -L "$OS_DIR/config/includes.chroot/etc/systemd/system/multi-user.target.wants/bedrock-first-run.service" ] || { printf 'error: first-run service is not enabled\n' >&2; exit 1; }
"$OS_DIR/scripts/validate-layout.sh"
"$OS_DIR/scripts/validate-boot.sh"
sh "$ROOT/installer/tests/test-target-selection.sh"
sh "$ROOT/installer/tests/test-linux-list-targets.sh"
sh "$ROOT/installer/tests/test-macos-list-targets.sh"
if command -v pwsh >/dev/null 2>&1; then
  sh "$ROOT/installer/tests/test-windows-list-targets.sh"
fi
sh "$ROOT/installer/tests/test-signed-image.sh"
sh "$ROOT/installer/tests/test-write-verified-image.sh"
sh "$ROOT/installer/tests/test-compressed-raw-write.sh"
sh "$ROOT/installer/tests/test-ui-shell.sh"
sh "$ROOT/installer/tests/test-desktop-shell.sh"
sh "$OS_DIR/tests/test-update-preferences.sh"
sh "$OS_DIR/tests/test-storage-health.sh"
sh "$OS_DIR/tests/test-storage-alerts.sh"
sh "$OS_DIR/tests/test-storage-plan.sh"
sh "$OS_DIR/tests/test-storage-operations.sh"
sh "$OS_DIR/tests/test-nas-management.sh"
sh "$OS_DIR/tests/test-storage-recovery.sh"
sh "$OS_DIR/tests/test-storage-activation.sh"
sh "$OS_DIR/tests/test-guided-storage.sh"
sh "$OS_DIR/tests/test-first-run-config.sh"
sh "$OS_DIR/tests/test-guided-install.sh"
sh "$OS_DIR/tests/test-install-acceptance-report.sh"
sh "$OS_DIR/tests/test-boot-test-report.sh"
sh "$OS_DIR/tests/test-boot-acceptance-capture.sh"
sh "$OS_DIR/tests/test-acceptance-workspace.sh"
sh "$OS_DIR/tests/test-0.2-0.3-acceptance.sh"
sh "$OS_DIR/tests/test-install-plan.sh"
sh "$OS_DIR/tests/test-install-image-simulator.sh"
sh "$OS_DIR/tests/test-protected-install-request.sh"
sh "$OS_DIR/tests/test-protected-system-writer.sh"
sh "$OS_DIR/tests/test-protected-loop-install.sh"
sh "$OS_DIR/tests/test-protected-installer-package.sh"

printf 'Bedrock image configuration is valid.\n'
