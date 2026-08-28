#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
checker="$ROOT/os/config/includes.chroot/usr/lib/bedrock/check-for-updates"
downloader="$ROOT/os/config/includes.chroot/usr/lib/bedrock/download-update"
verifier="$ROOT/os/config/includes.chroot/usr/lib/bedrock/verify-update-bundle"
default_policy="$ROOT/os/config/includes.chroot/usr/share/bedrock/default-update-policy.json"
channels="$ROOT/os/config/includes.chroot/usr/share/bedrock/release-channels.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/remote" "$work/state" "$work/settings"

openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes -days 1 -subj '/CN=Bedrock update download test/' \
  -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1
for name in root.erofs root.verity verity-sig.json uki.efi; do
  printf 'verified-%s-content\n' "$name" > "$work/remote/$name"
done
items='[]'
for name in root.erofs root.verity verity-sig.json uki.efi; do
  size=$(wc -c < "$work/remote/$name" | tr -d ' ')
  hash=$(sha256sum "$work/remote/$name" | awk '{print $1}')
  items=$(printf '%s' "$items" | jq -c --arg name "$name" --arg sha256 "$hash" --argjson size "$size" \
    '. + [{name:$name,size:$size,sha256:$sha256}]')
done
jq -S -c -n --argjson artifacts "$items" \
  '{architecture:"amd64",artifacts:$artifacts,generation:4,product:"Bedrock Server OS",schema:1,version:"0.4.0+test"}' \
  > "$work/remote/manifest.json"
openssl cms -sign -binary -noattr -md sha256 -in "$work/remote/manifest.json" \
  -signer "$work/cert.pem" -inkey "$work/key.pem" -outform DER -out "$work/remote/manifest.p7s"

run_checker() {
  BEDROCK_UPDATE_TEST_MODE=1 BEDROCK_UPDATE_POLICY_FILE="$work/settings/policy.json" \
  BEDROCK_UPDATE_DEFAULT_POLICY="$default_policy" BEDROCK_UPDATE_STATE_DIR="$work/state" \
  BEDROCK_UPDATE_CERT="$work/cert.pem" BEDROCK_UPDATE_CHANNELS_FILE="$channels" BEDROCK_UPDATE_SOURCE_DIR="$work/remote" \
  BEDROCK_TEST_NOW=1787900000 "$checker" --manual
}
run_downloader() {
  BEDROCK_UPDATE_TEST_MODE=1 BEDROCK_UPDATE_POLICY_FILE="$work/settings/policy.json" \
  BEDROCK_UPDATE_DEFAULT_POLICY="$default_policy" BEDROCK_UPDATE_STATE_DIR="$work/state" \
  BEDROCK_UPDATE_CERT="$work/cert.pem" BEDROCK_UPDATE_CHANNELS_FILE="$channels" BEDROCK_UPDATE_SOURCE_DIR="$work/remote" \
  BEDROCK_VERIFY_UPDATE="$verifier" "$downloader"
}
run_checker >/dev/null
mkdir -p "$work/state/bundles/4"
head -c 7 "$work/remote/root.erofs" > "$work/state/bundles/4/.root.erofs.part"
run_downloader |
  jq -e '.status == "downloaded" and .generation == 4 and .installed == false' >/dev/null
cmp -s "$work/remote/root.erofs" "$work/state/bundles/4/root.erofs"
"$verifier" "$work/state/bundles/4" "$work/cert.pem" >/dev/null
[ ! -e "$work/state/bundles/4/.root.erofs.part" ]

printf 'corrupt\n' > "$work/state/bundles/4/uki.efi"
run_downloader >/dev/null
cmp -s "$work/remote/uki.efi" "$work/state/bundles/4/uki.efi"

rm -f "$work/remote/root.verity" "$work/state/bundles/4/root.verity"
printf partial > "$work/state/bundles/4/.root.verity.part"
if run_downloader >/dev/null 2>&1; then
  printf 'error: downloader accepted a missing source artifact\n' >&2
  exit 1
fi
[ -s "$work/state/bundles/4/.root.verity.part" ] || { printf 'error: interrupted partial download was not retained\n' >&2; exit 1; }

printf 'Bedrock verified update download, resume, repair, and interruption tests passed.\n'
