#!/bin/sh
set -eu

[ "$#" -eq 4 ] || { printf 'usage: %s VERSION TYPE IMAGE OUTPUT_DIR\n' "$0" >&2; exit 2; }
version=$1
type=$2
image=$3
output=$4
: "${BEDROCK_RELEASE_KEY:?set BEDROCK_RELEASE_KEY to the protected release signing key}"
: "${BEDROCK_RELEASE_CERT:?set BEDROCK_RELEASE_CERT to its certificate}"

printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$' ||
  { printf 'error: invalid release version\n' >&2; exit 2; }
case "$type" in iso|raw-zst) ;; *) printf 'error: image type must be iso or raw-zst\n' >&2; exit 2;; esac
[ -s "$image" ] || { printf 'error: release image is missing or empty\n' >&2; exit 1; }
for tool in jq openssl; do command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }; done

name=$(basename "$image")
printf '%s' "$name" | grep -Eq '^bedrock-os-amd64\.(iso|raw\.zst)$' ||
  { printf 'error: image filename is not an approved Bedrock release artifact\n' >&2; exit 1; }
case "$type:$name" in iso:*.iso|raw-zst:*.raw.zst) ;; *) printf 'error: image type does not match its filename\n' >&2; exit 1;; esac

if command -v sha256sum >/dev/null 2>&1; then hash=$(sha256sum "$image" | awk '{print $1}'); else hash=$(shasum -a 256 "$image" | awk '{print $1}'); fi
size=$(stat -c %s "$image" 2>/dev/null || stat -f %z "$image")
if [ "$type" = raw-zst ]; then
  command -v zstd >/dev/null 2>&1 || { printf 'error: zstd is required for raw image releases\n' >&2; exit 1; }
  zstd -t "$image" >/dev/null 2>&1 || { printf 'error: compressed raw image is invalid\n' >&2; exit 1; }
  write_size=$(zstd -dc "$image" | wc -c | tr -d ' ')
  if command -v sha256sum >/dev/null 2>&1; then write_hash=$(zstd -dc "$image" | sha256sum | awk '{print $1}'); else write_hash=$(zstd -dc "$image" | shasum -a 256 | awk '{print $1}'); fi
else
  write_size=$size
  write_hash=$hash
fi
mkdir -p "$output"
cp "$image" "$output/$name"
jq -S -c -n --arg version "$version" --arg type "$type" --arg name "$name" --arg sha256 "$hash" --argjson size "$size" \
  --arg write_sha256 "$write_hash" --argjson write_size "$write_size" \
  '{architecture:"amd64",artifact:{name:$name,sha256:$sha256,size:$size,type:$type,write_sha256:$write_sha256,write_size:$write_size},product:"Bedrock Server OS",schema:1,version:$version}' \
  > "$output/manifest.json"
openssl cms -sign -binary -noattr -md sha256 -in "$output/manifest.json" -signer "$BEDROCK_RELEASE_CERT" \
  -inkey "$BEDROCK_RELEASE_KEY" -outform DER -out "$output/manifest.p7s"
printf 'Created signed Bedrock %s release %s.\n' "$type" "$version"
