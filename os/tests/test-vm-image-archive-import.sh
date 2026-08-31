#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
archive_importer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/import-vm-image-archive"
direct_importer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/import-vm-image"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,images:[]}' > "$work/images.json"
printf 'archive bytes\n' > "$work/upload.zip"
printf 'disk-image-data\n' > "$work/member"
cat > "$work/bin/unzip" <<'EOF'
#!/bin/sh
case "$1" in
  -Z1) printf '%s\n' "${MOCK_ZIP_ENTRIES:-debian-test.qcow2}" ;;
  -Z) printf '%s\n' "-rw-------  1.0 unx 16 b- 16 stor 26-Aug-31 00:00 debian-test.qcow2" ;;
  -p) cat "$MOCK_ZIP_MEMBER" ;;
  *) exit 2 ;;
esac
EOF
cat > "$work/bin/qemu-img" <<'EOF'
#!/bin/sh
printf '%s\n' '{"format":"qcow2","virtual-size":1073741824,"actual-size":16}'
EOF
chmod +x "$work/bin/unzip" "$work/bin/qemu-img"
archive_hash=$(sha256sum "$work/upload.zip" | awk '{print $1}'); archive_size=$(stat -c %s "$work/upload.zip")
image_hash=$(sha256sum "$work/member" | awk '{print $1}'); image_size=$(stat -c %s "$work/member")
authorize() { jq -n --arg ah "$archive_hash" --arg ih "$image_hash" --argjson as "$archive_size" --argjson is "$image_size" \
  '{schema:1,name:"debian-test",type:"qcow2",archive_sha256:$ah,archive_size_bytes:$as,sha256:$ih,size_bytes:$is,confirmation:("IMPORT ZIP debian-test "+$ah)}' > "$work/request.json"; }
run() { PATH="$work/bin:$PATH" MOCK_ZIP_MEMBER="$work/member" BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_IMAGES="$work/images.json" BEDROCK_VM_IMPORTER="$direct_importer" "$archive_importer" "$work/request.json" "$work/upload.zip"; }
authorize
run | jq -e '.status=="imported" and .name=="debian-test" and .type=="qcow2"' >/dev/null
cmp "$work/member" "$work/state/images/debian-test.qcow2"
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
rm -rf "$work/state/images"; jq -n '{schema:1,images:[]}' > "$work/images.json"; authorize
MOCK_ZIP_ENTRIES='debian-test.qcow2
extra.txt' must_fail run
jq '.confirmation="IMPORT ZIP wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"; must_fail run
printf 'VM ZIP image import tests passed.\n'
