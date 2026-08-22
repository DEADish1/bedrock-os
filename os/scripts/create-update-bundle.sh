#!/bin/sh
set -eu

[ "$#" -eq 4 ] || { printf 'usage: %s VERSION GENERATION ARTIFACT_DIR OUTPUT_DIR\n' "$0" >&2; exit 2; }
version=$1
generation=$2
artifacts=$3
output=$4
printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$' || { printf 'error: invalid update version\n' >&2; exit 2; }
printf '%s' "$generation" | grep -Eq '^[1-9][0-9]*$' || { printf 'error: generation must be a positive integer\n' >&2; exit 2; }
: "${BEDROCK_UPDATE_KEY:?set BEDROCK_UPDATE_KEY to the protected update signing key}"
: "${BEDROCK_UPDATE_CERT:?set BEDROCK_UPDATE_CERT to its certificate}"
for tool in jq openssl sha256sum stat; do command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }; done

files='root.erofs root.verity verity-sig.json uki.efi'
for name in $files; do [ -s "$artifacts/$name" ] || { printf 'error: missing update artifact %s\n' "$name" >&2; exit 1; }; done
mkdir -p "$output"
manifest="$output/manifest.json"
items='[]'
for name in $files; do
  hash=$(sha256sum "$artifacts/$name" | awk '{print $1}')
  size=$(stat -c %s "$artifacts/$name" 2>/dev/null || stat -f %z "$artifacts/$name")
  items=$(printf '%s' "$items" | jq -c --arg name "$name" --arg sha256 "$hash" --argjson size "$size" '. + [{name:$name,sha256:$sha256,size:$size}]')
  cp "$artifacts/$name" "$output/$name"
done
jq -S -c -n --arg version "$version" --argjson generation "$generation" --argjson artifacts "$items" \
  '{architecture:"amd64",artifacts:$artifacts,generation:$generation,product:"Bedrock Server OS",schema:1,version:$version}' > "$manifest"
openssl cms -sign -binary -noattr -md sha256 -in "$manifest" -signer "$BEDROCK_UPDATE_CERT" \
  -inkey "$BEDROCK_UPDATE_KEY" -outform DER -out "$output/manifest.p7s"
printf 'Created signed Bedrock update bundle generation %s.\n' "$generation"
