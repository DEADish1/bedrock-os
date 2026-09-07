#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
collector="$ROOT/os/config/includes.chroot/usr/lib/bedrock/collect-image-status"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
jq -n '{schema:1,images:[{name:"installer",type:"iso",sha256:("a"*64),size_bytes:1024,path:"/var/lib/bedrock/virtualization/images/installer.iso"},{name:"converted",type:"qcow2",sha256:("b"*64),size_bytes:2048,path:"/var/lib/bedrock/virtualization/images/converted.qcow2"}]}' > "$work/images.json"
jq -n '{schema:1,conversions:[{source:"source",source_sha256:("c"*64),source_type:"vmdk",target:"converted",target_sha256:("b"*64),target_type:"qcow2"}]}' > "$work/provenance.json"
BEDROCK_IMAGE_STATUS_TEST_MODE=1 BEDROCK_IMAGE_STATUS_IMAGES="$work/images.json" BEDROCK_IMAGE_STATUS_PROVENANCE="$work/provenance.json" BEDROCK_IMAGE_STATUS_OUTPUT="$work/status.json" "$collector"
jq -e '.images[0].converted==false and .images[1].converted==true and ([.images[]|keys]|all(index("path")|not))' "$work/status.json" >/dev/null
ln -s "$work/status.json" "$work/unsafe.json"
if BEDROCK_IMAGE_STATUS_TEST_MODE=1 BEDROCK_IMAGE_STATUS_IMAGES="$work/images.json" BEDROCK_IMAGE_STATUS_PROVENANCE="$work/provenance.json" BEDROCK_IMAGE_STATUS_OUTPUT="$work/unsafe.json" "$collector" 2>/dev/null; then
  printf 'error: collector accepted an indirect output\n' >&2; exit 1
fi
printf 'Privacy-safe VM image status tests passed.\n'
