#!/bin/sh
set -eu

usage() {
  printf 'usage: %s OUTPUT_DIR SLOT VERITY_CERT\n' "$0" >&2
  exit 2
}

[ "$#" -eq 3 ] || usage
out=$1
slot=$2
cert=$3
case "$slot" in a|b) ;; *) printf 'error: slot must be a or b\n' >&2; exit 2 ;; esac

image="$out/bedrock-root-$slot.erofs"
verity="$out/bedrock-root-$slot.verity"
root_hash_file="$out/bedrock-root-$slot.roothash"
root_hash_raw="$out/bedrock-root-$slot.roothash.bin"
signature="$out/bedrock-root-$slot.roothash.p7s"
signature_json="$out/bedrock-root-$slot.verity-sig.json"

for file in "$image" "$verity" "$root_hash_file" "$root_hash_raw" "$signature" "$signature_json" "$cert"; do
  [ -s "$file" ] || { printf 'error: required root artifact is missing: %s\n' "$file" >&2; exit 1; }
done
for tool in jq openssl veritysetup; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 1; }
done

root_hash=$(tr -d '\n' < "$root_hash_file")
[ "$(jq -r '.rootHash' "$signature_json")" = "$root_hash" ] || { printf 'error: signature metadata root hash differs\n' >&2; exit 1; }
json_signature=$(jq -r '.signature' "$signature_json")
file_signature=$(openssl base64 -A -in "$signature")
[ "$json_signature" = "$file_signature" ] || { printf 'error: signature metadata payload differs\n' >&2; exit 1; }

veritysetup verify "$image" "$verity" "$root_hash"
openssl cms -verify -binary -inform DER -in "$signature" -content "$root_hash_raw" \
  -certfile "$cert" -CAfile "$cert" -purpose any -out /dev/null >/dev/null 2>&1

printf 'Verified immutable root slot %s.\n' "$slot"
