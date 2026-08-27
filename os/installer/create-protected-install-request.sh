#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { printf 'usage: %s PLAN.json\n' "$0" >&2; exit 2; }
plan=$1
[ -f "$plan" ] && [ ! -L "$plan" ] || { printf 'error: installation plan is missing or indirect\n' >&2; exit 1; }
for tool in jq sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: %s is required\n' "$tool" >&2; exit 2; }
done

if [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ]; then
  : "${BEDROCK_TEST_REQUEST_SESSION:?test mode requires BEDROCK_TEST_REQUEST_SESSION}"
  : "${BEDROCK_TEST_NOW_UNIX:?test mode requires BEDROCK_TEST_NOW_UNIX}"
  session=$BEDROCK_TEST_REQUEST_SESSION
  created_unix=$BEDROCK_TEST_NOW_UNIX
else
  [ -r /proc/sys/kernel/random/uuid ] || { printf 'error: secure request identity source is unavailable\n' >&2; exit 1; }
  session=$(cat /proc/sys/kernel/random/uuid)
  created_unix=$(date +%s)
fi

plan_sha256=$(sha256sum "$plan" | awk '{print $1}')
request=$(jq -c \
  --arg session "$session" \
  --argjson created_unix "$created_unix" \
  --arg plan_sha256 "$plan_sha256" '
  select(
    .schema == 1 and .operation == "install-bedrock-system" and
    .source == "packaged-signed-live-system" and
    (.target | type == "object") and
    (.confirmation | type == "string" and length > 0 and length <= 1024) and
    (.layout.sha256 | type == "string") and
    .preserve_existing_data == false and
    .requires_fresh_inventory == true and
    .requires_exclusive_whole_disk == true and
    .ready_for_writer == false
  ) |
  {
    schema: 1,
    operation: "install-bedrock-system",
    session_id: $session,
    created_unix: $created_unix,
    artifact_name: "bedrock-os-amd64.raw",
    plan_sha256: $plan_sha256,
    layout_sha256: .layout.sha256,
    target_id: .target.id,
    target_snapshot: .target,
    confirmation: .confirmation
  }
' "$plan")
[ -n "$request" ] || { printf 'error: installation plan cannot create a protected request\n' >&2; exit 1; }
[ "$(printf '%s' "$request" | wc -c | tr -d ' ')" -le 16384 ] || {
  printf 'error: protected installation request exceeds its size limit\n' >&2
  exit 1
}
printf '%s\n' "$request"
