#!/bin/sh
set -eu

report=${1:-}
[ -n "$report" ] && [ -f "$report" ] || { printf 'usage: %s REPORT.json\n' "$0" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }

jq -e '
  .schema == 1 and
  (.image_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.platform == "qemu" or .platform == "vmware" or .platform == "hyper-v" or .platform == "physical") and
  (.cpu_vendor == "intel" or .cpu_vendor == "amd") and
  .uefi == true and .healthy_boot == true and .persistent_reboot == true and
  .inventory.cpu == true and .inventory.memory == true and
  .inventory.disk == true and .inventory.network == true
' "$report" >/dev/null || {
  printf 'error: boot-test report is incomplete or does not record a passing test\n' >&2
  exit 1
}

printf 'Bedrock boot-test report is valid: %s\n' "$report"
