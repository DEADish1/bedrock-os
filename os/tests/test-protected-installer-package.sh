#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
stager="$ROOT/os/installer/stage-protected-installer.sh"
sh -n "$stager"

if ! command -v rustc >/dev/null 2>&1; then
  printf 'Bedrock protected installer package test skipped: rustc unavailable.\n'
  exit 0
fi
for tool in jq sha256sum stat; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'error: protected installer package test requires %s\n' "$tool" >&2
    exit 2
  }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/root"
BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER= BEDROCK_REQUIRE_PRODUCTION_TRUST=0 \
  sh "$stager" stage "$work/root"

manifest="$work/root/usr/share/bedrock/installer/package-manifest.sha256"
(cd "$work/root" && sha256sum -c usr/share/bedrock/installer/package-manifest.sha256 >/dev/null)
jq -e '.schema == 1 and .writer_enabled == false and (.layout_sha256 | test("^[0-9a-f]{64}$"))' \
  "$work/root/usr/share/bedrock/installer/package.json" >/dev/null
[ "$(stat -c %a "$work/root/usr/sbin/bedrock-install-system")" = 755 ]
[ "$(stat -c %a "$work/root/usr/lib/bedrock/bedrock-system-writer")" = 755 ]
[ "$(stat -c %a "$manifest")" = 644 ]
grep -q '/usr/lib/bedrock/installer' "$work/root/usr/sbin/bedrock-install-system"
grep -q 'package-manifest.sha256' "$work/root/usr/sbin/bedrock-install-system"
grep -q 'writer_enabled == true' "$work/root/usr/sbin/bedrock-install-system"
grep -q '/usr/share/bedrock/installer/bedrock-amd64.json' \
  "$work/root/usr/lib/bedrock/installer/preflight-protected-install.sh"
if "$work/root/usr/lib/bedrock/bedrock-system-writer" >/dev/null 2>&1; then
  printf 'error: staged development writer did not fail closed\n' >&2
  exit 1
fi

sh "$stager" remove "$work/root"
[ ! -e "$manifest" ] && [ ! -e "$work/root/usr/sbin/bedrock-install-system" ] || {
  printf 'error: protected installer staging cleanup was incomplete\n' >&2
  exit 1
}

mkdir -p "$work/tampered-root"
BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER= BEDROCK_REQUIRE_PRODUCTION_TRUST=0 \
  sh "$stager" stage "$work/tampered-root"
printf '\n' >> "$work/tampered-root/usr/share/bedrock/installer/package.json"
if sh "$stager" remove "$work/tampered-root" >/dev/null 2>&1; then
  printf 'error: staging cleanup accepted a package that differed from its manifest\n' >&2
  exit 1
fi

mkdir -p "$work/production-root"
BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER=I_ACCEPT_REAL_SYSTEM_DISK_DATA_LOSS \
BEDROCK_REQUIRE_PRODUCTION_TRUST=1 \
  sh "$stager" stage "$work/production-root"
jq -e '.schema == 1 and .writer_enabled == true' \
  "$work/production-root/usr/share/bedrock/installer/package.json" >/dev/null
sh "$stager" remove "$work/production-root"

printf 'Bedrock protected installer staging and cleanup tests passed.\n'
