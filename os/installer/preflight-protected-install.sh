#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PATH=/usr/sbin:/usr/bin:/sbin:/bin
LC_ALL=C
export PATH LC_ALL
[ "$#" -eq 1 ] || { printf 'usage: %s REQUEST.json\n' "$0" >&2; exit 2; }
request=$1
[ -f "$request" ] && [ ! -L "$request" ] || { printf 'error: protected request is missing or indirect\n' >&2; exit 1; }
[ "$(wc -c < "$request" | tr -d ' ')" -le 16384 ] || {
  printf 'error: protected request exceeds its size limit\n' >&2
  exit 1
}
for tool in jq sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 2; }
done

if [ "$SCRIPT_DIR" = /usr/lib/bedrock/installer ]; then
  layout=/usr/share/bedrock/installer/bedrock-amd64.json
  adapter="$SCRIPT_DIR/linux-list-targets.sh"
  validator="$SCRIPT_DIR/validate-install-target.sh"
  verifier="$SCRIPT_DIR/verify-disk-image.sh"
else
  ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
  layout="$ROOT/os/layout/bedrock-amd64.json"
  adapter="$ROOT/installer/adapters/linux-list-targets.sh"
  validator="$ROOT/os/installer/validate-install-target.sh"
  verifier="$ROOT/os/scripts/verify-disk-image.sh"
fi
package_dir=/run/live/medium/bedrock
inventory=
inventory_is_temporary=0
cleanup() { [ "$inventory_is_temporary" -eq 0 ] || rm -f "$inventory"; }
trap cleanup EXIT INT TERM

if [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ]; then
  : "${BEDROCK_TEST_LAYOUT:?test mode requires BEDROCK_TEST_LAYOUT}"
  : "${BEDROCK_TEST_PACKAGE_DIR:?test mode requires BEDROCK_TEST_PACKAGE_DIR}"
  : "${BEDROCK_TEST_INVENTORY:?test mode requires BEDROCK_TEST_INVENTORY}"
  : "${BEDROCK_TEST_NOW_UNIX:?test mode requires BEDROCK_TEST_NOW_UNIX}"
  layout=$BEDROCK_TEST_LAYOUT
  package_dir=$BEDROCK_TEST_PACKAGE_DIR
  inventory=$BEDROCK_TEST_INVENTORY
  now=$BEDROCK_TEST_NOW_UNIX
else
  [ "$(id -u)" -eq 0 ] || { printf 'error: protected installation preflight requires root\n' >&2; exit 1; }
  unset BEDROCK_LSBLK_JSON BEDROCK_ROOT_PARENT BEDROCK_TEST_LAYOUT \
    BEDROCK_TEST_PACKAGE_DIR BEDROCK_TEST_INVENTORY BEDROCK_TEST_NOW_UNIX \
    BEDROCK_TEST_SKIP_GPT
  inventory=$(mktemp)
  inventory_is_temporary=1
  sh "$adapter" > "$inventory"
  now=$(date +%s)
fi

for file in "$layout" "$inventory"; do
  [ -f "$file" ] && [ ! -L "$file" ] || { printf 'error: protected preflight input is missing or indirect\n' >&2; exit 1; }
done

jq -e --argjson now "$now" '
  (keys | sort) == (["artifact_name","confirmation","created_unix","layout_sha256","operation","plan_sha256","schema","session_id","target_id","target_snapshot"] | sort) and
  .schema == 1 and .operation == "install-bedrock-system" and
  (.session_id | type == "string" and test("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")) and
  (.created_unix | type == "number" and floor == . and . <= ($now + 5) and . >= ($now - 120)) and
  .artifact_name == "bedrock-os-amd64.raw" and
  (.plan_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.layout_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.target_id | type == "string" and length > 0 and length <= 512) and
  (.confirmation | type == "string" and length > 0 and length <= 1024 and (contains("\n") | not)) and
  (.target_snapshot | type == "object") and
  (.target_snapshot | keys | sort) == (["id","model","mounted","path","read_only","removable","size_bytes","system"] | sort)
' "$request" >/dev/null || { printf 'error: invalid, stale, or unexpected protected installation request\n' >&2; exit 1; }

layout_hash=$(sha256sum "$layout" | awk '{print $1}')
request_layout_hash=$(jq -r .layout_sha256 "$request")
[ "$request_layout_hash" = "$layout_hash" ] || { printf 'error: installation layout changed after confirmation\n' >&2; exit 1; }

target_id=$(jq -r .target_id "$request")
confirmation=$(jq -r .confirmation "$request")
fresh_target=$(sh "$validator" "$inventory" "$target_id" "$confirmation" "$layout")
request_target=$(jq -c .target_snapshot "$request")
[ "$(printf '%s' "$fresh_target" | jq -S -c .)" = "$(printf '%s' "$request_target" | jq -S -c .)" ] || {
  printf 'error: selected system disk changed after confirmation\n' >&2
  exit 1
}

image="$package_dir/bedrock-os-amd64.raw"
checksum="$package_dir/bedrock-os-amd64.raw.sha256"
for file in "$image" "$checksum"; do
  [ -f "$file" ] && [ ! -L "$file" ] || { printf 'error: packaged installation image is missing or indirect\n' >&2; exit 1; }
done
expected_hash=$(awk 'NF == 2 {print $1; exit}' "$checksum")
expected_name=$(awk 'NF == 2 {print $2; exit}' "$checksum" | sed 's/^\*//')
[ "$expected_name" = bedrock-os-amd64.raw ] && printf '%s' "$expected_hash" | grep -Eq '^[0-9a-f]{64}$' || {
  printf 'error: packaged installation checksum manifest is invalid\n' >&2
  exit 1
}
[ "$(sha256sum "$image" | awk '{print $1}')" = "$expected_hash" ] || {
  printf 'error: packaged installation image failed checksum verification\n' >&2
  exit 1
}

image_size=$(wc -c < "$image" | tr -d ' ')
minimum=$(jq -r .minimum_disk_bytes "$layout")
capacity=$(printf '%s' "$fresh_target" | jq -r .size_bytes)
[ "$image_size" -eq "$minimum" ] && [ "$capacity" -ge "$image_size" ] || {
  printf 'error: packaged image size is incompatible with the selected system disk\n' >&2
  exit 1
}
if [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ] && [ "${BEDROCK_TEST_SKIP_GPT:-0}" = 1 ]; then
  : # Tests use a deliberately small fixture image that cannot contain the production GPT.
elif [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ]; then
  BEDROCK_INSTALLER_TEST_MODE=1 sh "$verifier" "$image" "$layout" >/dev/null
else
  sh "$verifier" "$image" >/dev/null
fi

jq -n -c \
  --arg session "$(jq -r .session_id "$request")" \
  --arg target_id "$target_id" '
  {
    schema: 1,
    session_id: $session,
    target_id: $target_id,
    preflight_complete: true,
    ready_for_writer: false,
    blocked_reason: "Preflight cannot authorize physical writing by itself. No disk was opened."
  }
'
