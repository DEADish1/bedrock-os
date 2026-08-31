#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
creator=$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-api-token
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
printf '{"schema":1,"tokens":[]}\n' > "$work/tokens.json"
token=$(printf 'b%.0s' $(seq 1 64))
result=$(BEDROCK_API_TEST_MODE=1 BEDROCK_API_STATE_ROOT="$work" BEDROCK_API_TOKENS="$work/tokens.json" BEDROCK_API_TOKEN="$token" BEDROCK_API_NOW=2026-08-31T00:00:00Z "$creator" dashboard)
printf '%s' "$result" | jq -e --arg token "$token" '.status=="created" and .name=="dashboard" and .token==$token and .shown_once==true' >/dev/null
expected=$(printf '%s' "$token" | sha256sum | awk '{print $1}')
jq -e --arg expected "$expected" '.schema==1 and (.tokens|length)==1 and .tokens[0].name=="dashboard" and .tokens[0].sha256==$expected and .tokens[0].revoked==false' "$work/tokens.json" >/dev/null
! grep -q "$token" "$work/tokens.json"
if BEDROCK_API_TEST_MODE=1 BEDROCK_API_STATE_ROOT="$work" BEDROCK_API_TOKENS="$work/tokens.json" BEDROCK_API_TOKEN="$token" "$creator" dashboard >/dev/null 2>&1; then
  printf 'error: duplicate API token name was accepted\n' >&2
  exit 1
fi
printf 'Bedrock API token tests passed.\n'
