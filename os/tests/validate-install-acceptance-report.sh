#!/bin/sh
set -eu

report=${1:-}
[ -n "$report" ] && [ -f "$report" ] && [ ! -L "$report" ] || {
  printf 'usage: %s REPORT.json\n' "$0" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }
[ "$(wc -c < "$report" | tr -d ' ')" -le 65536 ] || {
  printf 'error: system-install acceptance report is too large\n' >&2
  exit 1
}

required_mode=physical
[ "${BEDROCK_ALLOW_FIXTURE_INSTALL_REPORT:-0}" = 1 ] && required_mode=fixture
jq -e --arg mode "$required_mode" '
  (keys | sort) == (["checks","completed_at","image_sha256","mode","schema","target"] | sort) and
  .schema == 1 and .mode == $mode and
  (.completed_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  (.image_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.target | keys | sort) == (["disposable","model","path","size_bytes"] | sort) and
  (.target.path | type == "string" and
    (if $mode == "physical" then test("^/dev/(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$")
     else . == "/dev/test-system" end)) and
  (.target.model | type == "string" and length > 0 and length <= 256 and (test("[\\r\\n]") | not)) and
  (.target.size_bytes | type == "number" and floor == . and . >= 34359738368 and . <= 9007199254740991) and
  .target.disposable == true and
  (.checks | keys | sort) == ([
    "acceptance_writer_enabled","boot_health_marker","booted_from_target","exact_confirmation",
    "first_run_completed","fresh_inventory","gpt_verified","hardware_inventory_present",
    "persistent_reboot","persistent_state_checked","raw_write_complete","reread_verified",
    "terminal_free_install"
  ] | sort) and all(.checks[]; . == true) and
  (has("serial_number") | not) and (.target | has("serial_number") | not) and
  (has("username") | not) and (has("hostname") | not) and (has("ip_address") | not)
' "$report" >/dev/null || {
  printf 'error: system-install acceptance report is incomplete, unsafe, or not the required mode\n' >&2
  exit 1
}
printf 'Bedrock %s system-install acceptance report is valid: %s\n' "$required_mode" "$report"
