#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
helper="$ROOT/os/scripts/bedrock-acceptance-workspace.sh"
boot_fixture="$ROOT/os/tests/boot-test-report.example.json"
install_fixture="$ROOT/os/tests/install-acceptance-report.example.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

printf 'verified Bedrock test image\n' > "$work/bedrock.iso"
sh "$helper" init "$work/bedrock.iso" "$work/evidence" > "$work/init.out"
sha=$(cat "$work/evidence/IMAGE_SHA256")

case "$sha" in
  *[!0-9a-f]*|'') printf 'error: init stored an invalid SHA-256\n' >&2; exit 1 ;;
esac
[ "${#sha}" -eq 64 ] || { printf 'error: init stored a short SHA-256\n' >&2; exit 1; }
grep -F 'No disk was opened or written.' "$work/init.out" >/dev/null

if sh "$helper" status "$work/evidence" > "$work/missing.out" 2>&1; then
  printf 'error: empty workspace was reported complete\n' >&2
  exit 1
fi
[ "$(grep -c '^\[missing\]' "$work/missing.out")" -eq 6 ] || {
  printf 'error: empty workspace did not identify all six missing reports\n' >&2
  exit 1
}

sh "$helper" init "$work/bedrock.iso" "$work/evidence" >/dev/null
printf 'another image\n' > "$work/other.iso"
if sh "$helper" init "$work/other.iso" "$work/evidence" >/dev/null 2>&1; then
  printf 'error: workspace accepted a different image\n' >&2
  exit 1
fi
[ "$(cat "$work/evidence/IMAGE_SHA256")" = "$sha" ] || {
  printf 'error: rejected image changed the workspace binding\n' >&2
  exit 1
}
ln -s "$work/bedrock.iso" "$work/image-link.iso"
if sh "$helper" init "$work/image-link.iso" "$work/linked-evidence" >/dev/null 2>&1; then
  printf 'error: workspace accepted an indirect image\n' >&2
  exit 1
fi

jq --arg sha "$sha" '.mode = "physical" | .image_sha256 = $sha | .platform = "vmware" | .platform_generation = null' \
  "$boot_fixture" > "$work/evidence/vmware.json"
jq --arg sha "$sha" '.mode = "physical" | .image_sha256 = $sha | .platform = "hyper-v" | .platform_generation = "generation-2"' \
  "$boot_fixture" > "$work/evidence/hyper-v-generation-2.json"
jq --arg sha "$sha" '.mode = "physical" | .image_sha256 = $sha | .platform = "physical" | .platform_generation = null | .cpu_vendor = "intel"' \
  "$boot_fixture" > "$work/evidence/physical-intel.json"
jq --arg sha "$sha" '.mode = "physical" | .image_sha256 = $sha | .platform = "physical" | .platform_generation = null | .cpu_vendor = "amd"' \
  "$boot_fixture" > "$work/evidence/physical-amd.json"
jq -n --arg sha "$sha" '{
  schema:2,mode:"physical",platform:"linux",completed_at:"2026-08-25T00:00:00Z",
  boot_completed_at:"2026-08-25T01:00:00Z",image_sha256:$sha,
  target:{id:"linux:acceptance-usb",path:"/dev/sdz",model:"Disposable USB",size_bytes:8589934592,disposable:true},
  checks:{fresh_inventory:true,exact_confirmation:true,write_completed:true,
    reread_checksum:true,cache_synchronized:true,manual_removal_safe:true,
    booted_from_media:true,guided_installer_opened:true}
}' > "$work/evidence/disposable-usb.json"
jq --arg sha "$sha" '.mode = "physical" | .image_sha256 = $sha | .target.path = "/dev/nvme0n1"' \
  "$install_fixture" > "$work/evidence/disposable-system-install.json"

sh "$helper" status "$work/evidence" > "$work/complete.out"
[ "$(grep -c '^\[ok\]' "$work/complete.out")" -eq 6 ] || {
  printf 'error: complete workspace did not validate all six reports\n' >&2
  exit 1
}
grep -F "physical acceptance bundle is complete for image $sha" "$work/complete.out" >/dev/null

jq '.cpu_vendor = "amd"' "$work/evidence/physical-intel.json" > "$work/bad.json"
mv "$work/bad.json" "$work/evidence/physical-intel.json"
if sh "$helper" status "$work/evidence" > "$work/invalid.out" 2>&1; then
  printf 'error: workspace accepted a report with the wrong role\n' >&2
  exit 1
fi
grep -F '[invalid] Physical Intel' "$work/invalid.out" >/dev/null

printf 'Bedrock acceptance-workspace tests passed.\n'
