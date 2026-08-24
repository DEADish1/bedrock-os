#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
planner="$ROOT/os/installer/create-install-plan.sh"
creator="$ROOT/os/installer/create-protected-install-request.sh"
preflight="$ROOT/os/installer/preflight-protected-install.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/package"

jq '.minimum_disk_bytes = 4096' "$ROOT/os/layout/bedrock-amd64.json" > "$work/layout.json"
truncate -s 4096 "$work/package/bedrock-os-amd64.raw"
(cd "$work/package" && sha256sum bedrock-os-amd64.raw > bedrock-os-amd64.raw.sha256)
jq -n '{
  schema:1,generated_at:"2026-08-24T00:00:00Z",targets:[{
    id:"linux:protected-test",path:"/dev/test-system",model:"Protected Test Disk",size_bytes:8192,
    removable:false,system:false,mounted:false,read_only:false
  }]
}' > "$work/inventory.json"
confirmation='INSTALL BEDROCK — Protected Test Disk — /dev/test-system — 8192'

BEDROCK_INSTALLER_TEST_MODE=1 BEDROCK_TEST_LAYOUT="$work/layout.json" \
  sh "$planner" "$work/inventory.json" linux:protected-test "$confirmation" > "$work/plan.json"
BEDROCK_INSTALLER_TEST_MODE=1 \
BEDROCK_TEST_REQUEST_SESSION=123e4567-e89b-42d3-a456-426614174000 \
BEDROCK_TEST_NOW_UNIX=1787598000 \
  sh "$creator" "$work/plan.json" > "$work/request.json"

run_preflight() {
  BEDROCK_INSTALLER_TEST_MODE=1 \
  BEDROCK_TEST_LAYOUT="$work/layout.json" \
  BEDROCK_TEST_PACKAGE_DIR="$work/package" \
  BEDROCK_TEST_INVENTORY="${1:-$work/inventory.json}" \
  BEDROCK_TEST_NOW_UNIX=1787598000 \
  BEDROCK_TEST_SKIP_GPT=1 \
    sh "$preflight" "${2:-$work/request.json}"
}

run_preflight | jq -e '
  .schema == 1 and .session_id == "123e4567-e89b-42d3-a456-426614174000" and
  .target_id == "linux:protected-test" and .preflight_complete == true and
  .ready_for_writer == false and (.blocked_reason | contains("No disk was opened"))
' >/dev/null

reject_request() {
  name=$1
  filter=$2
  jq "$filter" "$work/request.json" > "$work/$name.json"
  if run_preflight "$work/inventory.json" "$work/$name.json" >/dev/null 2>&1; then
    printf 'error: protected preflight accepted %s request\n' "$name" >&2
    exit 1
  fi
}
reject_request unknown-field '.unexpected = true'
reject_request stale '.created_unix = 1787597879'
reject_request future '.created_unix = 1787598006'
reject_request bad-session '.session_id = "not-a-session"'
reject_request path-injection '.artifact_name = "../bedrock-os-amd64.raw"'
reject_request changed-target '.target_snapshot.model = "Another Disk"'

jq '.targets[0].mounted = true' "$work/inventory.json" > "$work/mounted.json"
if run_preflight "$work/mounted.json" >/dev/null 2>&1; then
  printf 'error: protected preflight accepted a newly mounted target\n' >&2
  exit 1
fi
jq '.targets[0].size_bytes = 16384' "$work/inventory.json" > "$work/resized.json"
if run_preflight "$work/resized.json" >/dev/null 2>&1; then
  printf 'error: protected preflight accepted a changed target capacity\n' >&2
  exit 1
fi

cp "$work/package/bedrock-os-amd64.raw" "$work/original.raw"
printf 'x' | dd of="$work/package/bedrock-os-amd64.raw" bs=1 seek=0 conv=notrunc status=none
if run_preflight >/dev/null 2>&1; then
  printf 'error: protected preflight accepted a changed packaged image\n' >&2
  exit 1
fi
cp "$work/original.raw" "$work/package/bedrock-os-amd64.raw"

cp "$work/request.json" "$work/oversized.json"
dd if=/dev/zero bs=17000 count=1 status=none >> "$work/oversized.json"
if run_preflight "$work/inventory.json" "$work/oversized.json" >/dev/null 2>&1; then
  printf 'error: protected preflight accepted an oversized request\n' >&2
  exit 1
fi

printf 'Bedrock protected installation request preflight tests passed.\n'
