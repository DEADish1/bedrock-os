#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
checker="$ROOT/os/config/includes.chroot/usr/lib/bedrock/check-for-updates"
settings="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-update-settings"
setup="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-setup-updates"
default_policy="$ROOT/os/config/includes.chroot/usr/share/bedrock/default-update-policy.json"
channels="$ROOT/os/config/includes.chroot/usr/share/bedrock/release-channels.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/remote" "$work/state" "$work/settings"

openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes -days 1 -subj '/CN=Bedrock update preference test/' \
  -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1
hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
jq -n --arg hash "$hash" '
  {schema:1,product:"Bedrock Server OS",version:"0.3.0+test",generation:3,architecture:"amd64",
   artifacts:[
     {name:"root.erofs",size:1,sha256:$hash},
     {name:"root.verity",size:1,sha256:$hash},
     {name:"verity-sig.json",size:1,sha256:$hash},
     {name:"uki.efi",size:1,sha256:$hash}
   ]}
' > "$work/remote/manifest.json"
openssl cms -sign -binary -noattr -md sha256 -in "$work/remote/manifest.json" \
  -signer "$work/cert.pem" -inkey "$work/key.pem" -outform DER \
  -out "$work/remote/manifest.p7s"

run_checker() {
  test_source=${TEST_SOURCE_DIR:-$work/remote}
  BEDROCK_UPDATE_TEST_MODE=1 BEDROCK_UPDATE_POLICY_FILE="$work/settings/policy.json" \
  BEDROCK_UPDATE_DEFAULT_POLICY="$default_policy" BEDROCK_UPDATE_STATE_DIR="$work/state" \
  BEDROCK_UPDATE_CERT="$work/cert.pem" BEDROCK_UPDATE_CHANNELS_FILE="$channels" \
  BEDROCK_UPDATE_SOURCE_DIR="$test_source" BEDROCK_TEST_NOW=1787600000 \
    "$checker" "$@"
}
run_settings() {
  BEDROCK_UPDATE_TEST_MODE=1 BEDROCK_UPDATE_POLICY_FILE="$work/settings/policy.json" \
  BEDROCK_UPDATE_DEFAULT_POLICY="$default_policy" BEDROCK_UPDATE_CHECKER="$checker" \
  BEDROCK_UPDATE_STATE_DIR="$work/state" BEDROCK_UPDATE_CERT="$work/cert.pem" \
  BEDROCK_UPDATE_SOURCE_DIR="$work/remote" BEDROCK_TEST_NOW=1787600000 \
    "$settings" "$@"
}

TEST_SOURCE_DIR="$work/source-that-does-not-exist" run_checker |
  jq -e '.status == "disabled" and .network_contacted == false' >/dev/null
[ ! -e "$work/state/last-check.json" ]
run_checker --manual | jq -e '.status == "available" and .available_generation == 3' >/dev/null

BEDROCK_UPDATE_TEST_MODE=1 BEDROCK_UPDATE_SETTINGS="$settings" \
BEDROCK_UPDATE_POLICY_FILE="$work/settings/policy.json" BEDROCK_UPDATE_DEFAULT_POLICY="$default_policy" \
BEDROCK_UPDATE_CHECKER="$checker" "$setup" automatic >/dev/null
run_settings show | jq -e '.automatic_checks == true and .setup_choice_recorded == true' >/dev/null
run_checker | jq -e '.status == "available"' >/dev/null

printf '3\n' > "$work/state/generation"
run_checker | jq -e '.status == "up-to-date" and .installed_generation == 3' >/dev/null
run_settings automatic-checks off >/dev/null
run_settings show | jq -e '.automatic_checks == false and .setup_choice_recorded == true' >/dev/null

jq '.generation = 4 | .version = "0.4.0-beta.1"' "$work/remote/manifest.json" > "$work/remote/manifest.tmp"
mv "$work/remote/manifest.tmp" "$work/remote/manifest.json"
openssl cms -sign -binary -noattr -md sha256 -in "$work/remote/manifest.json" \
  -signer "$work/cert.pem" -inkey "$work/key.pem" -outform DER -out "$work/remote/manifest.p7s"
if run_checker --manual >/dev/null 2>&1; then
  printf 'error: stable channel accepted a prerelease update\n' >&2
  exit 1
fi
if run_settings channel beta >/dev/null 2>&1; then
  printf 'error: beta channel did not require explicit risk acknowledgement\n' >&2
  exit 1
fi
run_settings channel beta I_ACCEPT_PRERELEASE_UPDATE_RISK >/dev/null
run_settings show | jq -e '.channel == "beta" and .schema == 2' >/dev/null
run_checker --manual | jq -e '.status == "available" and .available_channel == "beta"' >/dev/null
run_settings channel stable >/dev/null

cp "$work/state/last-check.json" "$work/last-good.json"
jq '.generation = 5' "$work/remote/manifest.json" > "$work/remote/manifest.tmp"
mv "$work/remote/manifest.tmp" "$work/remote/manifest.json"
if run_checker --manual >/dev/null 2>&1; then
  printf 'error: update checker accepted modified signed metadata\n' >&2
  exit 1
fi
cmp -s "$work/last-good.json" "$work/state/last-check.json" || {
  printf 'error: a failed update check replaced the last verified result\n' >&2
  exit 1
}

printf 'Bedrock update preferences, manual checks, signed metadata, and opt-out tests passed.\n'
