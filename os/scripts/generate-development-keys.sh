#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { printf 'usage: %s OUTPUT_DIR\n' "$0" >&2; exit 2; }
out=$1
[ "${BEDROCK_ALLOW_EPHEMERAL_KEYS:-0}" = 1 ] || { printf 'error: ephemeral keys require BEDROCK_ALLOW_EPHEMERAL_KEYS=1\n' >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { printf 'error: openssl is required\n' >&2; exit 1; }

mkdir -p "$out"
umask 077
key="$out/DO-NOT-SHIP-development.key"
cert="$out/DO-NOT-SHIP-development.crt"
openssl req -new -x509 -newkey rsa:3072 -sha256 -nodes -days 7 \
  -subj '/CN=Bedrock ephemeral CI development key/' \
  -keyout "$key" -out "$cert" >/dev/null 2>&1
printf '%s\n%s\n' "$key" "$cert"
