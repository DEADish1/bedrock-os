#!/bin/sh
set -eu

[ "$#" -eq 2 ] || { printf 'usage: %s IMAGE.iso true|false\n' "$0" >&2; exit 2; }
iso=$1
expected=$2
[ "$expected" = true ] || [ "$expected" = false ] || {
  printf 'error: expected protected-writer mode must be true or false\n' >&2
  exit 2
}
[ -f "$iso" ] && [ ! -L "$iso" ] || { printf 'error: live ISO is missing or indirect\n' >&2; exit 1; }
for tool in jq sha256sum unsquashfs xorriso; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: live installer verification requires %s\n' "$tool" >&2; exit 2; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
squashfs="$work/filesystem.squashfs"
rootfs="$work/root"
xorriso -osirrox on -indev "$iso" \
  -extract /live/filesystem.squashfs "$squashfs" >/dev/null 2>&1
[ -s "$squashfs" ] || { printf 'error: live filesystem is missing from ISO\n' >&2; exit 1; }
unsquashfs -quiet -d "$rootfs" "$squashfs" \
  usr/lib/bedrock usr/sbin/bedrock-install-system usr/share/bedrock/installer >/dev/null

manifest=usr/share/bedrock/installer/package-manifest.sha256
metadata=usr/share/bedrock/installer/package.json
for file in "$rootfs/$manifest" "$rootfs/$metadata"; do
  [ -f "$file" ] && [ ! -L "$file" ] || {
    printf 'error: protected installer metadata is missing from live filesystem\n' >&2
    exit 1
  }
done
(cd "$rootfs" && sha256sum -c "$manifest" >/dev/null) || {
  printf 'error: protected installer package inside ISO failed integrity verification\n' >&2
  exit 1
}
jq -e --argjson expected "$expected" '
  (keys | sort) == (["layout_sha256","schema","writer_enabled"] | sort) and
  .schema == 1 and .writer_enabled == $expected and
  (.layout_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
' "$rootfs/$metadata" >/dev/null || {
  printf 'error: protected installer build mode inside ISO is incorrect\n' >&2
  exit 1
}
[ -x "$rootfs/usr/lib/bedrock/bedrock-system-writer" ] && \
  [ -x "$rootfs/usr/sbin/bedrock-install-system" ] || {
  printf 'error: protected installer executables are unavailable inside ISO\n' >&2
  exit 1
}

printf 'Verified protected installer package inside live ISO (writer enabled: %s).\n' "$expected"
