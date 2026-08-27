#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator="$ROOT/os/tests/validate-0.2-0.3-acceptance.sh"
boot_fixture="$ROOT/os/tests/boot-test-report.example.json"
install_fixture="$ROOT/os/tests/install-acceptance-report.example.json"
usb_validator="$ROOT/installer/acceptance/validate-real-device-report.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

jq '.mode = "physical" | .platform = "vmware" | .platform_generation = null' \
  "$boot_fixture" > "$work/vmware.json"
jq '.mode = "physical" | .platform = "hyper-v" | .platform_generation = "generation-2"' \
  "$boot_fixture" > "$work/hyper-v.json"
jq '.mode = "physical" | .platform = "physical" | .platform_generation = null | .cpu_vendor = "intel"' \
  "$boot_fixture" > "$work/intel.json"
jq '.mode = "physical" | .platform = "physical" | .platform_generation = null | .cpu_vendor = "amd"' \
  "$boot_fixture" > "$work/amd.json"
jq -n --arg sha "$sha" '{
  schema:2,mode:"physical",platform:"linux",completed_at:"2026-08-25T00:00:00Z",
  boot_completed_at:"2026-08-25T01:00:00Z",
  image_sha256:$sha,
  target:{id:"linux:acceptance-usb",path:"/dev/sdz",model:"Disposable USB",size_bytes:8589934592,disposable:true},
  checks:{fresh_inventory:true,exact_confirmation:true,write_completed:true,
    reread_checksum:true,cache_synchronized:true,manual_removal_safe:true,
    booted_from_media:true,guided_installer_opened:true}
}' > "$work/usb.json"
jq '.mode = "physical" | .target.path = "/dev/nvme0n1"' \
  "$install_fixture" > "$work/install.json"

sh "$validator" "$sha" "$work/vmware.json" "$work/hyper-v.json" \
  "$work/intel.json" "$work/amd.json" "$work/usb.json" "$work/install.json" >/dev/null

must_reject_bundle() {
  label=$1
  shift
  if sh "$validator" "$@" >/dev/null 2>&1; then
    printf 'error: milestone validator accepted %s\n' "$label" >&2
    exit 1
  fi
}

jq '.image_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
  "$work/usb.json" > "$work/wrong-image.json"
must_reject_bundle 'mixed image hashes' "$sha" "$work/vmware.json" "$work/hyper-v.json" \
  "$work/intel.json" "$work/amd.json" "$work/wrong-image.json" "$work/install.json"
must_reject_bundle 'duplicate role reports' "$sha" "$work/vmware.json" "$work/hyper-v.json" \
  "$work/intel.json" "$work/intel.json" "$work/usb.json" "$work/install.json"
jq '.cpu_vendor = "amd"' "$work/intel.json" > "$work/wrong-intel.json"
must_reject_bundle 'wrong physical CPU vendor' "$sha" "$work/vmware.json" "$work/hyper-v.json" \
  "$work/wrong-intel.json" "$work/amd.json" "$work/usb.json" "$work/install.json"
must_reject_bundle 'fixture boot evidence' "$sha" "$boot_fixture" "$work/hyper-v.json" \
  "$work/intel.json" "$work/amd.json" "$work/usb.json" "$work/install.json"

must_reject_usb() {
  label=$1
  report=$2
  if sh "$usb_validator" "$report" >/dev/null 2>&1; then
    printf 'error: removable-media validator accepted %s\n' "$label" >&2
    exit 1
  fi
}

jq '.target.path = "/dev/sdz1"' "$work/usb.json" > "$work/partition.json"
must_reject_usb 'a Linux partition' "$work/partition.json"
jq '.completed_at = "2026-08-25T00:00:00Z trailing"' "$work/usb.json" > "$work/bad-time.json"
must_reject_usb 'a noncanonical timestamp' "$work/bad-time.json"
jq '.notes = "unreviewed extra data"' "$work/usb.json" > "$work/unknown.json"
must_reject_usb 'unknown fields' "$work/unknown.json"
jq '.target.serial_number = "private"' "$work/usb.json" > "$work/private.json"
must_reject_usb 'private target data' "$work/private.json"
jq '.boot_completed_at = null | .checks.booted_from_media = false |
    .checks.guided_installer_opened = false' "$work/usb.json" > "$work/unbooted.json"
must_reject_usb 'unbooted media' "$work/unbooted.json"
ln -s "$work/usb.json" "$work/usb-link.json"
must_reject_usb 'an indirect report' "$work/usb-link.json"

printf 'Bedrock 0.2/0.3 acceptance-bundle tests passed.\n'
