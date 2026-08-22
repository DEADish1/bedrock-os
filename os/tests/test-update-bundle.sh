#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
mkdir -p "$work/artifacts" "$work/bundle" "$work/keys"
truncate -s 4096 "$work/artifacts/root.erofs"
truncate -s 8192 "$work/artifacts/root.verity"
printf '{"rootHash":"%064d","signature":"test"}\n' 0 > "$work/artifacts/verity-sig.json"
truncate -s 16384 "$work/artifacts/uki.efi"

BEDROCK_ALLOW_EPHEMERAL_KEYS=1 "$ROOT/os/scripts/generate-development-keys.sh" "$work/keys" >/dev/null
key="$work/keys/DO-NOT-SHIP-development.key"
cert="$work/keys/DO-NOT-SHIP-development.crt"
BEDROCK_UPDATE_KEY="$key" BEDROCK_UPDATE_CERT="$cert" \
  "$ROOT/os/scripts/create-update-bundle.sh" 0.2.0-test 3 "$work/artifacts" "$work/bundle" >/dev/null
"$ROOT/os/config/includes.chroot/usr/lib/bedrock/verify-update-bundle" "$work/bundle" "$cert" >/dev/null

printf x >> "$work/bundle/root.erofs"
if "$ROOT/os/config/includes.chroot/usr/lib/bedrock/verify-update-bundle" "$work/bundle" "$cert" >/dev/null 2>&1; then
  printf 'error: tampered update artifact was accepted\n' >&2
  exit 1
fi
printf 'Bedrock signed update bundle accepted valid content and rejected tampering.\n'
