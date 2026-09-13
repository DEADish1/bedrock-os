#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool="$ROOT/os/config/includes.chroot/usr/lib/bedrock/initialize-remote-identity"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

BEDROCK_REMOTE_IDENTITY_TEST_MODE=1 BEDROCK_REMOTE_IDENTITY_DIR="$work/identity" "$tool" >/dev/null
private="$work/identity/server-private-key.pem"
public="$work/identity/server-public-key"
[ -s "$private" ] && [ -s "$public" ] && [ ! -L "$private" ] && [ ! -L "$public" ]
key=$(tr -d '\r\n' < "$public")
printf '%s' "$key" | grep -Eq '^[0-9a-f]{64}$'
[ "$(openssl pkey -in "$private" -pubout -outform DER 2>/dev/null | tail -c 32 | xxd -p -c 64)" = "$key" ]
before=$(sha256sum "$private" "$public")
BEDROCK_REMOTE_IDENTITY_TEST_MODE=1 BEDROCK_REMOTE_IDENTITY_DIR="$work/identity" "$tool" >/dev/null
[ "$before" = "$(sha256sum "$private" "$public")" ]
rm "$public"
BEDROCK_REMOTE_IDENTITY_TEST_MODE=1 BEDROCK_REMOTE_IDENTITY_DIR="$work/identity" "$tool" >/dev/null
[ "$(openssl pkey -in "$private" -pubout -outform DER 2>/dev/null | tail -c 32 | xxd -p -c 64)" = "$(tr -d '\r\n' < "$public")" ]
rm "$private"
if BEDROCK_REMOTE_IDENTITY_TEST_MODE=1 BEDROCK_REMOTE_IDENTITY_DIR="$work/identity" "$tool" >/dev/null 2>&1; then printf 'error: public-only remote identity was accepted\n' >&2; exit 1; fi
printf 'Atomic X25519 remote identity tests passed.\n'
