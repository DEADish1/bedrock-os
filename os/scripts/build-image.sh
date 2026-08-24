#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OS_DIR="$ROOT/os"
OUT_DIR="$OS_DIR/out"

[ "$(id -u)" -eq 0 ] || { printf 'error: run as root on Debian 13\n' >&2; exit 1; }
command -v lb >/dev/null 2>&1 || { printf 'error: live-build is required\n' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 1; }

installer_staged=0
cleanup_installer_stage() {
  [ "$installer_staged" -eq 0 ] || \
    "$OS_DIR/installer/stage-protected-installer.sh" remove "$OS_DIR/config/includes.chroot"
}
trap cleanup_installer_stage EXIT INT TERM

"$OS_DIR/scripts/validate-config.sh"
"$OS_DIR/tests/test-update-bundle.sh"
"$OS_DIR/tests/test-hardware-inventory.sh"
"$OS_DIR/tests/test-reproducibility-check.sh"
. "$OS_DIR/build.env"

SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)}
BEDROCK_SOURCE_COMMIT=${BEDROCK_SOURCE_COMMIT:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf unknown)}
export SOURCE_DATE_EPOCH TZ=UTC LC_ALL=C.UTF-8

mkdir -p "$OUT_DIR"
cd "$OS_DIR"
lb clean --purge
lb config
"$OS_DIR/installer/stage-protected-installer.sh" stage "$OS_DIR/config/includes.chroot"
installer_staged=1
lb build 2>&1 | tee "$OUT_DIR/build.log"
"$OS_DIR/installer/stage-protected-installer.sh" remove "$OS_DIR/config/includes.chroot"
installer_staged=0

ISO_SOURCE="$OS_DIR/${BEDROCK_IMAGE_NAME}.hybrid.iso"
[ -s "$ISO_SOURCE" ] || { printf 'error: live-build did not produce %s\n' "$ISO_SOURCE" >&2; exit 1; }
ISO_OUT="$OUT_DIR/${BEDROCK_IMAGE_NAME}.iso"
mv "$ISO_SOURCE" "$ISO_OUT"

cd "$OUT_DIR"
sha256sum "$(basename "$ISO_OUT")" > "$(basename "$ISO_OUT").sha256"

packages=$(find "$OS_DIR/chroot/var/lib/dpkg" -name status -type f -maxdepth 1 -print -quit 2>/dev/null || true)
if [ -n "$packages" ]; then
  awk '/^Package:/{p=$2}/^Version:/{print p"="$2}' "$packages" | LC_ALL=C sort > packages.lock
else
  : > packages.lock
fi

jq -n \
  --arg version "$BEDROCK_VERSION" \
  --arg distribution "$BEDROCK_DISTRIBUTION" \
  --arg architecture "$BEDROCK_ARCHITECTURE" \
  --arg source_date_epoch "$SOURCE_DATE_EPOCH" \
  --arg commit "$BEDROCK_SOURCE_COMMIT" \
  --arg live_build "$(lb --version 2>/dev/null | head -n1)" \
  '{schema:1,product:"Bedrock Server OS",version:$version,distribution:$distribution,architecture:$architecture,source_date_epoch:($source_date_epoch|tonumber),commit:$commit,live_build:$live_build}' \
  > bedrock-build-manifest.json

"$OS_DIR/scripts/verify-artifacts.sh" "$OUT_DIR"

if [ "${BEDROCK_BUILD_RAW:-0}" = 1 ]; then
  "$OS_DIR/scripts/build-raw-image.sh"
  "$OS_DIR/scripts/verify-artifacts.sh" "$OUT_DIR"
  "$OS_DIR/tests/test-update-install.sh" "$OUT_DIR/bedrock-os-amd64.raw" "$OUT_DIR/components"
  "$OS_DIR/tests/test-update-install.sh" "$OUT_DIR/bedrock-os-amd64.raw" "$OUT_DIR/components" bad
  "$OS_DIR/tests/test-ab-rollback.sh" "$OUT_DIR/bedrock-os-amd64.raw"
  "$OS_DIR/tests/test-uefi-boot.sh" "$OUT_DIR/bedrock-os-amd64.raw" a
  zstd -T0 -10 --force "$OUT_DIR/bedrock-os-amd64.raw" -o "$OUT_DIR/bedrock-os-amd64.raw.zst"
fi
