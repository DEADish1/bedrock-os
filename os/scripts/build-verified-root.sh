#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OS_DIR="$ROOT/os"

usage() {
  printf 'usage: %s ROOTFS_DIR SLOT OUTPUT_DIR\n' "$0" >&2
  exit 2
}

[ "$#" -eq 3 ] || usage
rootfs=$1
slot=$2
out=$3
case "$slot" in a|b) ;; *) printf 'error: slot must be a or b\n' >&2; exit 2 ;; esac
[ -d "$rootfs" ] || { printf 'error: root filesystem directory is missing\n' >&2; exit 1; }
: "${BEDROCK_VERITY_KEY:?set BEDROCK_VERITY_KEY to a protected signing key}"
: "${BEDROCK_VERITY_CERT:?set BEDROCK_VERITY_CERT to its certificate}"

for tool in jq mkfs.erofs openssl veritysetup xxd; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }
done

. "$OS_DIR/build.env"
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)}
export SOURCE_DATE_EPOCH TZ=UTC LC_ALL=C.UTF-8
mkdir -p "$out"

image="$out/bedrock-root-$slot.erofs"
verity="$out/bedrock-root-$slot.verity"
root_hash_file="$out/bedrock-root-$slot.roothash"
root_hash_raw="$out/bedrock-root-$slot.roothash.bin"
signature="$out/bedrock-root-$slot.roothash.p7s"
signature_json="$out/bedrock-root-$slot.verity-sig.json"

if [ "$slot" = a ]; then
  filesystem_uuid=00000000-0000-4000-8000-00000000000a
  verity_uuid=10000000-0000-4000-8000-00000000000a
else
  filesystem_uuid=00000000-0000-4000-8000-00000000000b
  verity_uuid=10000000-0000-4000-8000-00000000000b
fi

rm -f "$image" "$verity" "$root_hash_file" "$root_hash_raw" "$signature" "$signature_json"
mkfs.erofs -T "$SOURCE_DATE_EPOCH" -U "$filesystem_uuid" -L "bedrock-root-$slot" "$image" "$rootfs"
truncate -s 512M "$verity"
salt=$(sha256sum "$image" | awk '{print $1}')
format_output=$(veritysetup format --uuid="$verity_uuid" --salt="$salt" "$image" "$verity")
root_hash=$(printf '%s\n' "$format_output" | awk '/^Root hash:/{print $3}')
printf '%s' "$root_hash" | grep -Eq '^[0-9a-fA-F]{64}$' || { printf 'error: veritysetup returned an invalid root hash\n' >&2; exit 1; }
printf '%s\n' "$root_hash" > "$root_hash_file"
printf '%s' "$root_hash" | xxd -r -p > "$root_hash_raw"

openssl cms -sign -binary -noattr -nocerts -md sha256 \
  -in "$root_hash_raw" -signer "$BEDROCK_VERITY_CERT" -inkey "$BEDROCK_VERITY_KEY" \
  -outform DER -out "$signature"

signature_b64=$(openssl base64 -A -in "$signature")
jq -n --arg rootHash "$root_hash" --arg signature "$signature_b64" \
  '{rootHash:$rootHash,signature:$signature}' > "$signature_json"

veritysetup verify "$image" "$verity" "$root_hash"
"$OS_DIR/scripts/verify-verified-root.sh" "$out" "$slot" "$BEDROCK_VERITY_CERT"
printf 'Built verified immutable root slot %s in %s\n' "$slot" "$out"
