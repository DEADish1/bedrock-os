#!/bin/sh
set -eu

usage() {
  printf 'usage: %s IMAGE_SHA256 VMWARE.json HYPER-V.json INTEL.json AMD.json USB.json INSTALL.json\n' "$0" >&2
  exit 2
}

[ "$#" -eq 7 ] || usage
image_sha256=$1
vmware=$2
hyper_v=$3
intel=$4
amd=$5
usb=$6
install=$7

case "$image_sha256" in
  *[!0-9a-f]*|'') usage ;;
esac
[ "${#image_sha256}" -eq 64 ] || usage
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
boot_validator="$ROOT/os/tests/validate-boot-test-report.sh"
usb_validator="$ROOT/installer/acceptance/validate-real-device-report.sh"
install_validator="$ROOT/os/tests/validate-install-acceptance-report.sh"

canonical_report() {
  report_dir=$(dirname -- "$1")
  report_name=$(basename -- "$1")
  (CDPATH= cd -P -- "$report_dir" && printf '%s/%s\n' "$(pwd -P)" "$report_name")
}

paths=$(for report in "$vmware" "$hyper_v" "$intel" "$amd" "$usb" "$install"; do
  [ -f "$report" ] && [ ! -L "$report" ] || { printf 'error: acceptance report is missing or indirect: %s\n' "$report" >&2; exit 1; }
  canonical_report "$report"
done)
[ "$(printf '%s\n' "$paths" | LC_ALL=C sort -u | wc -l | tr -d ' ')" -eq 6 ] || {
  printf 'error: every acceptance role requires a distinct report file\n' >&2
  exit 1
}

sh "$boot_validator" "$vmware" >/dev/null
sh "$boot_validator" "$hyper_v" >/dev/null
sh "$boot_validator" "$intel" >/dev/null
sh "$boot_validator" "$amd" >/dev/null
sh "$usb_validator" "$usb" >/dev/null
sh "$install_validator" "$install" >/dev/null

jq -e --arg sha "$image_sha256" '.image_sha256 == $sha and .platform == "vmware" and .platform_generation == null' "$vmware" >/dev/null || {
  printf 'error: VMware evidence does not match the required image and platform\n' >&2
  exit 1
}
jq -e --arg sha "$image_sha256" '.image_sha256 == $sha and .platform == "hyper-v" and .platform_generation == "generation-2"' "$hyper_v" >/dev/null || {
  printf 'error: Hyper-V Generation 2 evidence does not match the required image and platform\n' >&2
  exit 1
}
jq -e --arg sha "$image_sha256" '.image_sha256 == $sha and .platform == "physical" and .cpu_vendor == "intel"' "$intel" >/dev/null || {
  printf 'error: physical Intel evidence does not match the required image and platform\n' >&2
  exit 1
}
jq -e --arg sha "$image_sha256" '.image_sha256 == $sha and .platform == "physical" and .cpu_vendor == "amd"' "$amd" >/dev/null || {
  printf 'error: physical AMD evidence does not match the required image and platform\n' >&2
  exit 1
}
jq -e --arg sha "$image_sha256" '.image_sha256 == $sha' "$usb" >/dev/null || {
  printf 'error: removable-media evidence does not use the required image\n' >&2
  exit 1
}
jq -e --arg sha "$image_sha256" '.image_sha256 == $sha' "$install" >/dev/null || {
  printf 'error: installed-system evidence does not use the required image\n' >&2
  exit 1
}

printf 'Bedrock 0.2/0.3 physical acceptance bundle is complete for image %s.\n' "$image_sha256"
