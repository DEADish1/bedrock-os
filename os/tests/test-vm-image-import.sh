#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
importer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/import-vm-image"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,images:[]}' > "$work/images.json"
printf 'disk-image-data\n' > "$work/upload.qcow2"
cat > "$work/bin/qemu-img" <<'EOF'
#!/bin/sh
printf '%s\n' '{"format":"qcow2","virtual-size":1073741824,"actual-size":16}'
EOF
cat > "$work/bin/file" <<'EOF'
#!/bin/sh
printf '%s\n' application/x-iso9660-image
EOF
chmod +x "$work/bin/qemu-img" "$work/bin/file"
hash=$(sha256sum "$work/upload.qcow2" | awk '{print $1}')
size=$(stat -c %s "$work/upload.qcow2")
jq -n --arg hash "$hash" --argjson size "$size" '{schema:1,name:"debian-test",type:"qcow2",sha256:$hash,size_bytes:$size,confirmation:("IMPORT QCOW2 debian-test "+$hash)}' > "$work/request.json"
run() { PATH="$work/bin:$PATH" BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_IMAGES="$work/images.json" "$importer" "$work/request.json" "$work/upload.qcow2"; }
run | jq -e '.status=="imported" and .attached==false and .type=="qcow2"' >/dev/null
[ -f "$work/state/images/debian-test.qcow2" ]
jq -e '.images|length==1 and .[0].name=="debian-test"' "$work/images.json" >/dev/null
cmp "$work/upload.qcow2" "$work/state/images/debian-test.qcow2"
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail run
rm -rf "$work/state/images"; jq -n '{schema:1,images:[]}' > "$work/images.json"
jq '.confirmation="IMPORT QCOW2 wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"; must_fail run
jq -n --arg hash "$hash" --argjson size "$size" '{schema:1,name:"debian-test",type:"qcow2",sha256:$hash,size_bytes:$size,confirmation:("IMPORT QCOW2 debian-test "+$hash)}' > "$work/request.json"
cat > "$work/bin/qemu-img" <<'EOF'
#!/bin/sh
printf '%s\n' '{"format":"qcow2","backing-filename":"/etc/passwd"}'
EOF
must_fail run
printf 'VM image import tests passed.\n'
