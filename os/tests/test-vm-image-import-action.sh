#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd); wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/import-uploaded-vm-image"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
printf source > "$work/upload.iso"; hash=$(sha256sum "$work/upload.iso" | awk '{print $1}')
cat > "$work/importer" <<'EOF'
#!/bin/sh
jq -c . "$1" >> "$BEDROCK_TEST_IMAGE_CALLS"; printf '%s\n' "$2" >> "$BEDROCK_TEST_UPLOAD_CALLS"
EOF
cat > "$work/recorder" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_TEST_TASK_CALLS"
EOF
chmod +x "$work/importer" "$work/recorder"
jq -n --arg hash "$hash" '{schema:1,name:"debian",type:"iso",sha256:$hash,size_bytes:6,confirmation:("IMPORT ISO debian "+$hash)}' > "$work/request.json"
BEDROCK_IMAGE_IMPORT_ACTION_TEST_MODE=1 BEDROCK_IMAGE_IMPORT_ACTION_IMPORTER="$work/importer" BEDROCK_IMAGE_IMPORT_ACTION_UPLOAD="$work/upload.iso" BEDROCK_IMAGE_IMPORT_ACTION_MANIFEST="$work/upload.json" BEDROCK_RECORD_API_TASK="$work/recorder" BEDROCK_TEST_IMAGE_CALLS="$work/image-calls" BEDROCK_TEST_UPLOAD_CALLS="$work/upload-calls" BEDROCK_TEST_TASK_CALLS="$work/task-calls" "$wrapper" "$work/request.json"
[ ! -e "$work/upload.iso" ]; jq -e '.name=="debian" and .type=="iso"' "$work/image-calls" >/dev/null; grep -q ' succeeded ' "$work/task-calls"
printf 'Uploaded image import action tests passed.\n'
