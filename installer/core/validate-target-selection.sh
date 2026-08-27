#!/bin/sh
set -eu

inventory=${1:-}
target_id=${2:-}
confirmation=${3:-}
[ -f "$inventory" ] && [ -n "$target_id" ] || {
  printf 'usage: %s INVENTORY.json TARGET_ID CONFIRMATION\n' "$0" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }

jq -e '.schema == 1 and (.generated_at | type == "string") and (.targets | type == "array")' "$inventory" >/dev/null || {
  printf 'error: invalid target inventory\n' >&2
  exit 1
}

count=$(jq --arg id "$target_id" '[.targets[] | select(.id == $id)] | length' "$inventory")
[ "$count" -eq 1 ] || { printf 'error: target identity is missing or ambiguous\n' >&2; exit 1; }

target=$(jq -c --arg id "$target_id" '.targets[] | select(.id == $id)' "$inventory")
printf '%s\n' "$target" | jq -e '
  (.id | type == "string" and length > 0) and
  (.path | type == "string" and length > 0) and
  (.model | type == "string" and length > 0) and
  (.size_bytes | type == "number" and . >= 8589934592 and floor == .) and
  .removable == true and .system == false and .mounted == false and .read_only == false
' >/dev/null || { printf 'error: selected target is not safe and eligible\n' >&2; exit 1; }

expected=$(printf '%s\n' "$target" | jq -r '"ERASE \(.model) — \(.path) — \(.size_bytes)"')
[ "$confirmation" = "$expected" ] || { printf 'error: confirmation does not exactly name the selected target\n' >&2; exit 1; }

printf '%s\n' "$target"
