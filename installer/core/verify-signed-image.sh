#!/bin/sh
set -eu

[ "$#" -eq 3 ] || { printf 'usage: %s RELEASE_DIR TRUSTED_CERT EXPECTED_IMAGE_NAME\n' "$0" >&2; exit 2; }
release=$1
cert=$2
expected_name=$3
manifest="$release/manifest.json"
signature="$release/manifest.p7s"
[ -s "$manifest" ] && [ -s "$signature" ] && [ -s "$cert" ] ||
  { printf 'error: release manifest, signature, or trusted certificate is missing\n' >&2; exit 1; }
for tool in jq openssl; do command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }; done

openssl cms -verify -binary -inform DER -in "$signature" -content "$manifest" \
  -CAfile "$cert" -purpose any -out /dev/null >/dev/null 2>&1 ||
  { printf 'error: release manifest signature is invalid\n' >&2; exit 1; }

jq -e '
  .schema == 1 and .product == "Bedrock Server OS" and .architecture == "amd64" and
  (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+([+-][A-Za-z0-9.-]+)?$")) and
  (.artifact | type == "object") and
  (.artifact.name | test("^bedrock-os-amd64\\.(iso|raw\\.zst)$")) and
  (.artifact.type == "iso" or .artifact.type == "raw-zst") and
  ((.artifact.type == "iso" and (.artifact.name | endswith(".iso"))) or
   (.artifact.type == "raw-zst" and (.artifact.name | endswith(".raw.zst")))) and
  (.artifact.sha256 | test("^[0-9a-f]{64}$")) and
  (.artifact.size | type == "number" and . > 0 and floor == .) and
  (.artifact.write_sha256 | test("^[0-9a-f]{64}$")) and
  (.artifact.write_size | type == "number" and . > 0 and floor == .) and
  (if .artifact.type == "iso" then
    .artifact.write_sha256 == .artifact.sha256 and .artifact.write_size == .artifact.size
   else true end) and
  (keys | sort == ["architecture","artifact","product","schema","version"]) and
  (.artifact | keys | sort == ["name","sha256","size","type","write_sha256","write_size"])
' "$manifest" >/dev/null || { printf 'error: release manifest schema is invalid\n' >&2; exit 1; }

name=$(jq -r '.artifact.name' "$manifest")
[ "$name" = "$expected_name" ] || { printf 'error: signed image name does not match the requested download\n' >&2; exit 1; }
file="$release/$name"
[ -f "$file" ] || { printf 'error: signed image is missing\n' >&2; exit 1; }
expected_size=$(jq -r '.artifact.size' "$manifest")
actual_size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file")
[ "$actual_size" = "$expected_size" ] || { printf 'error: signed image size is incorrect\n' >&2; exit 1; }
expected_hash=$(jq -r '.artifact.sha256' "$manifest")
if command -v sha256sum >/dev/null 2>&1; then actual_hash=$(sha256sum "$file" | awk '{print $1}'); else actual_hash=$(shasum -a 256 "$file" | awk '{print $1}'); fi
[ "$actual_hash" = "$expected_hash" ] || { printf 'error: signed image checksum is invalid\n' >&2; exit 1; }
if [ "$(jq -r .artifact.type "$manifest")" = raw-zst ]; then
  command -v zstd >/dev/null 2>&1 || { printf 'error: zstd is required to verify this raw image\n' >&2; exit 1; }
  zstd -t "$file" >/dev/null 2>&1 || { printf 'error: compressed raw image is invalid\n' >&2; exit 1; }
  expanded_size=$(zstd -dc "$file" | wc -c | tr -d ' ')
  [ "$expanded_size" = "$(jq -r .artifact.write_size "$manifest")" ] || { printf 'error: expanded raw image size is incorrect\n' >&2; exit 1; }
  if command -v sha256sum >/dev/null 2>&1; then expanded_hash=$(zstd -dc "$file" | sha256sum | awk '{print $1}'); else expanded_hash=$(zstd -dc "$file" | shasum -a 256 | awk '{print $1}'); fi
  [ "$expanded_hash" = "$(jq -r .artifact.write_sha256 "$manifest")" ] || { printf 'error: expanded raw image checksum is invalid\n' >&2; exit 1; }
fi

printf 'Verified signed Bedrock image %s (%s).\n' "$name" "$(jq -r .version "$manifest")"
