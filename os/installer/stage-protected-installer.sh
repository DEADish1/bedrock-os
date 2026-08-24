#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
[ "$#" -eq 2 ] || { printf 'usage: %s stage|remove ROOTFS\n' "$0" >&2; exit 2; }
operation=$1
[ "$operation" = stage ] || [ "$operation" = remove ] || {
  printf 'error: protected installer staging operation is invalid\n' >&2
  exit 2
}
[ -d "$2" ] && [ ! -L "$2" ] || { printf 'error: staging root is missing or indirect\n' >&2; exit 1; }
rootfs=$(CDPATH= cd -- "$2" && pwd)
case $rootfs in /|/usr|/usr/local) printf 'error: refusing broad protected installer staging root\n' >&2; exit 1 ;; esac

manifest=usr/share/bedrock/installer/package-manifest.sha256
metadata=usr/share/bedrock/installer/package.json
packaged_files='
usr/lib/bedrock/bedrock-system-writer
usr/lib/bedrock/installer/create-install-plan.sh
usr/lib/bedrock/installer/create-protected-install-request.sh
usr/lib/bedrock/installer/finalize-protected-layout.sh
usr/lib/bedrock/installer/linux-list-targets.sh
usr/lib/bedrock/installer/preflight-protected-install.sh
usr/lib/bedrock/installer/validate-install-target.sh
usr/lib/bedrock/installer/verify-disk-image.sh
usr/sbin/bedrock-install-system
usr/share/bedrock/installer/bedrock-amd64.json
usr/share/bedrock/installer/package.json
'

remove_package() {
  printf '%s' "$packaged_files" | while IFS= read -r file; do
    [ -n "$file" ] || continue
    rm -f "$rootfs/$file"
  done
  rm -f "$rootfs/$manifest"
  rmdir "$rootfs/usr/lib/bedrock/installer" 2>/dev/null || true
  rmdir "$rootfs/usr/share/bedrock/installer" 2>/dev/null || true
  rmdir "$rootfs/usr/sbin" 2>/dev/null || true
  rmdir "$rootfs/usr/lib/bedrock" 2>/dev/null || true
  rmdir "$rootfs/usr/share/bedrock" 2>/dev/null || true
}

if [ "$operation" = remove ]; then
  [ -f "$rootfs/$manifest" ] && [ ! -L "$rootfs/$manifest" ] || {
    printf 'error: protected installer staging manifest is missing or indirect\n' >&2
    exit 1
  }
  (cd "$rootfs" && sha256sum -c "$manifest" >/dev/null) || {
    printf 'error: staged protected installer differs from its manifest\n' >&2
    exit 1
  }
  remove_package
  exit 0
fi

for tool in install mktemp rustc sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: staging requires %s\n' "$tool" >&2; exit 2; }
done
[ ! -e "$rootfs/$manifest" ] || { printf 'error: protected installer is already staged\n' >&2; exit 1; }
printf '%s' "$packaged_files" | while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ ! -e "$rootfs/$file" ] || { printf 'error: refusing to overwrite staged path: %s\n' "$file" >&2; exit 1; }
done

work=$(mktemp -d)
complete=0
cleanup() {
  rm -rf "$work"
  [ "$complete" -eq 1 ] || remove_package
}
trap cleanup EXIT INT TERM
package_root="$work/root"
mkdir -p \
  "$package_root/usr/lib/bedrock/installer" \
  "$package_root/usr/sbin" \
  "$package_root/usr/share/bedrock/installer"

sh "$ROOT/os/installer/build-protected-system-writer.sh" \
  "$package_root/usr/lib/bedrock/bedrock-system-writer"
for source_name in create-install-plan.sh create-protected-install-request.sh \
  finalize-protected-layout.sh preflight-protected-install.sh validate-install-target.sh; do
  install -m 0755 "$ROOT/os/installer/$source_name" \
    "$package_root/usr/lib/bedrock/installer/$source_name"
done
install -m 0755 "$ROOT/installer/adapters/linux-list-targets.sh" \
  "$package_root/usr/lib/bedrock/installer/linux-list-targets.sh"
install -m 0755 "$ROOT/os/scripts/verify-disk-image.sh" \
  "$package_root/usr/lib/bedrock/installer/verify-disk-image.sh"
install -m 0755 "$ROOT/os/installer/write-protected-install.sh" \
  "$package_root/usr/sbin/bedrock-install-system"
install -m 0644 "$ROOT/os/layout/bedrock-amd64.json" \
  "$package_root/usr/share/bedrock/installer/bedrock-amd64.json"

writer_enabled=false
[ -z "${BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER:-}" ] || writer_enabled=true
layout_sha=$(sha256sum "$ROOT/os/layout/bedrock-amd64.json" | awk '{print $1}')
printf '{"schema":1,"writer_enabled":%s,"layout_sha256":"%s"}\n' \
  "$writer_enabled" "$layout_sha" > "$package_root/$metadata"
chmod 0644 "$package_root/$metadata"

package_manifest="$work/package-manifest.sha256"
printf '%s' "$packaged_files" | while IFS= read -r file; do
  [ -n "$file" ] || continue
  (cd "$package_root" && sha256sum "$file")
done > "$package_manifest"

mkdir -p \
  "$rootfs/usr/lib/bedrock/installer" \
  "$rootfs/usr/sbin" \
  "$rootfs/usr/share/bedrock/installer"
printf '%s' "$packaged_files" | while IFS= read -r file; do
  [ -n "$file" ] || continue
  mode=0644
  case $file in *.sh|usr/sbin/*|usr/lib/bedrock/bedrock-system-writer) mode=0755 ;; esac
  install -m "$mode" "$package_root/$file" "$rootfs/$file"
done
install -m 0644 "$package_manifest" "$rootfs/$manifest"
(cd "$rootfs" && sha256sum -c "$manifest" >/dev/null)
complete=1
