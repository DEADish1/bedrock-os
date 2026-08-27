#!/bin/sh
set -eu

report=${1:-}
[ -n "$report" ] && [ -f "$report" ] && [ ! -L "$report" ] || {
  printf 'usage: %s REPORT.json\n' "$0" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }
[ "$(wc -c < "$report" | tr -d ' ')" -le 65536 ] || {
  printf 'error: boot-test report is too large\n' >&2
  exit 1
}

required_mode=physical
[ "${BEDROCK_ALLOW_FIXTURE_BOOT_REPORT:-0}" = 1 ] && required_mode=fixture
jq -e --arg mode "$required_mode" '
  (keys | sort) == ([
    "completed_at","cpu_vendor","firmware_mode","healthy_boot","image_sha256","inventory",
    "mode","persistent_reboot","platform","platform_generation","privacy_reviewed",
    "same_image_verified","schema","secure_boot"
  ] | sort) and
  .schema == 2 and .mode == $mode and
  (.completed_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  (.image_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.platform == "vmware" or .platform == "hyper-v" or .platform == "physical") and
  (if .platform == "hyper-v" then .platform_generation == "generation-2"
   else .platform_generation == null end) and
  (.cpu_vendor == "intel" or .cpu_vendor == "amd") and
  .firmware_mode == "uefi" and
  (.secure_boot == "disabled" or .secure_boot == "bedrock-key-trusted") and
  .same_image_verified == true and .healthy_boot == true and .persistent_reboot == true and
  (.inventory | keys | sort) == (["cpu","disk","memory","network"] | sort) and
  all(.inventory[]; . == true) and .privacy_reviewed == true and
  (has("serial_number") | not) and (has("username") | not) and
  (has("hostname") | not) and (has("ip_address") | not) and (has("mac_address") | not)
' "$report" >/dev/null || {
  printf 'error: boot-test report is incomplete, unsafe, or not the required mode\n' >&2
  exit 1
}

printf 'Bedrock %s boot-test report is valid: %s\n' "$required_mode" "$report"
