#!/bin/sh
set -eu

report=${1:-}
[ -n "$report" ] && [ -f "$report" ] && [ ! -L "$report" ] || {
  printf 'usage: %s REPORT.json\n' "$0" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }
[ "$(wc -c < "$report" | tr -d ' ')" -le 65536 ] || {
  printf 'error: removable-media acceptance report is too large\n' >&2
  exit 1
}

required_mode=physical
[ "${BEDROCK_ALLOW_FIXTURE_ACCEPTANCE_REPORT:-0}" = 1 ] && required_mode=fixture
jq -e --arg mode "$required_mode" '
  (keys | sort) == (["checks","completed_at","image_sha256","mode","platform","schema","target"] | sort) and
  .schema == 1 and .mode == $mode and
  (.platform == "linux" or .platform == "macos" or .platform == "windows") and
  (.completed_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  (.image_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.target | keys | sort) == (["disposable","id","model","path","size_bytes"] | sort) and
  (.target.id | type == "string" and length > 0 and length <= 256 and (test("[\\r\\n]") | not)) and
  (.target.path | type == "string" and length > 0 and length <= 4096 and (test("[\\r\\n]") | not)) and
  (.target.model | type == "string" and length > 0 and length <= 256 and (test("[\\r\\n]") | not)) and
  (.target.size_bytes | type == "number" and . >= 8589934592 and . <= 9007199254740991 and floor == .) and
  (.mode == "fixture" or
    (.platform == "linux" and (.target.path | test("^/dev/(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$"))) or
    (.platform == "macos" and (.target.path | test("^/dev/disk[0-9]+$"))) or
    (.platform == "windows" and (.target.path | startswith("\\\\.\\PhysicalDrive")) and
      (.target.path | ltrimstr("\\\\.\\PhysicalDrive") | test("^[0-9]+$")))) and
  .target.disposable == true and
  (.checks | keys | sort) == ([
    "cache_synchronized","exact_confirmation","fresh_inventory",
    "manual_removal_safe","reread_checksum","write_completed"
  ] | sort) and all(.checks[]; . == true)
' "$report" >/dev/null || {
  printf 'error: removable-media acceptance report is incomplete, unsafe, or not the required mode\n' >&2
  exit 1
}
printf 'Bedrock %s-device acceptance report is valid: %s\n' "$required_mode" "$report"
