#!/bin/sh
set -eu

report=${1:-}
[ -n "$report" ] && [ -f "$report" ] || { printf 'usage: %s REPORT.json\n' "$0" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }

required_mode=physical
[ "${BEDROCK_ALLOW_FIXTURE_ACCEPTANCE_REPORT:-0}" = 1 ] && required_mode=fixture
jq -e --arg mode "$required_mode" '
  .schema == 1 and .mode == $mode and .platform == "linux" and
  (.completed_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) and
  (.image_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.target.id | type == "string" and length > 0) and
  (.target.path | type == "string" and length > 0) and
  (.target.model | type == "string" and length > 0) and
  (.target.size_bytes | type == "number" and . >= 8589934592 and floor == .) and
  .target.disposable == true and
  .checks.fresh_inventory == true and .checks.exact_confirmation == true and
  .checks.write_completed == true and .checks.reread_checksum == true and
  .checks.cache_synchronized == true and .checks.manual_removal_safe == true and
  (has("serial_number") | not) and (.target | has("serial_number") | not)
' "$report" >/dev/null || {
  printf 'error: acceptance report is incomplete, unsafe, or not the required mode\n' >&2
  exit 1
}
printf 'Bedrock %s-device acceptance report is valid: %s\n' "$required_mode" "$report"
