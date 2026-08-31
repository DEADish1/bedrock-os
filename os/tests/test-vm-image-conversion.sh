#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
converter="$ROOT/os/config/includes.chroot/usr/lib/bedrock/convert-vm-image"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state/images"
printf 'source-vmdk\n' > "$work/state/images/source.vmdk"
source_hash=$(sha256sum "$work/state/images/source.vmdk" | awk '{print $1}'); source_size=$(stat -c %s "$work/state/images/source.vmdk")
MSYS2_ARG_CONV_EXCL='*' jq -n --arg hash "$source_hash" --argjson size "$source_size" --arg path "$work/state/images/source.vmdk" '{schema:1,images:[{name:"source",type:"vmdk",sha256:$hash,size_bytes:$size,path:$path}]}' > "$work/images.json"
jq -n '{schema:1,conversions:[]}' > "$work/provenance.json"
cat > "$work/bin/qemu-img" <<'EOF'
#!/bin/sh
if [ "$1" = convert ]; then
  eval "destination=\${$#}"
  printf 'converted-qcow2\n' > "$destination"
else
  case "$4" in *.vmdk) format=vmdk ;; *) format=qcow2 ;; esac
  printf '{"format":"%s","virtual-size":1073741824,"actual-size":16}\n' "$format"
fi
EOF
chmod +x "$work/bin/qemu-img"
authorize() { jq -n --arg hash "$source_hash" '{schema:1,source:"source",source_sha256:$hash,target:"converted",target_type:"qcow2",confirmation:("CONVERT IMAGE source "+$hash+" TO QCOW2 converted")}' > "$work/request.json"; }
run() { PATH="$work/bin:$PATH" BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_IMAGES="$work/images.json" BEDROCK_VM_PROVENANCE="$work/provenance.json" "$converter" "$work/request.json"; }
authorize; run | jq -e '.status=="converted" and .target=="converted" and .type=="qcow2"' >/dev/null
[ -f "$work/state/images/converted.qcow2" ]; jq -e '.images|length==2' "$work/images.json" >/dev/null
jq -e --arg hash "$source_hash" '.conversions|length==1 and .[0].source_sha256==$hash and .[0].target=="converted"' "$work/provenance.json" >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail run
jq '.target="other"|.confirmation="wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"; must_fail run
printf 'VM image conversion tests passed.\n'
