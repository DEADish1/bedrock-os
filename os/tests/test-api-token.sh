#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
creator=$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-api-token
manager=$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-api-tokens
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
listing=$(BEDROCK_API_TEST_MODE=1 BEDROCK_API_STATE_ROOT="$work" BEDROCK_API_TOKENS="$work/tokens.json" "$manager" list)
printf '%s' "$listing" | jq -e '.tokens==[{name:"dashboard",created_at:"2026-08-31T00:00:00Z",revoked:false}] and ([..|objects|keys[]]|index("sha256")|not)' >/dev/null
revoked=$(BEDROCK_API_TEST_MODE=1 BEDROCK_API_STATE_ROOT="$work" BEDROCK_API_TOKENS="$work/tokens.json" "$manager" revoke dashboard)
printf '%s' "$revoked" | jq -e '.status=="revoked" and .name=="dashboard"' >/dev/null
jq -e '.tokens[0].revoked==true and (.tokens[0].sha256|length)==64' "$work/tokens.json" >/dev/null
if BEDROCK_API_TEST_MODE=1 BEDROCK_API_STATE_ROOT="$work" BEDROCK_API_TOKENS="$work/tokens.json" "$manager" revoke dashboard >/dev/null 2>&1; then
  printf 'error: already revoked API token was revoked again\n' >&2
  exit 1
fi
# A full store can recover a revoked name without replacing any active grant.
jq -n --arg hash "$expected" '{schema:1,tokens:[range(0;16) | {name:("slot-"+tostring),sha256:$hash,created_at:"2026-08-31T00:00:00Z",revoked:(.==0)}]}' > "$work/tokens.json"
cp "$work/tokens.json" "$work/before.json"
fresh=$(printf 'c%.0s' $(seq 1 64))
if BEDROCK_API_TEST_MODE=1 BEDROCK_API_STATE_ROOT="$work" BEDROCK_API_TOKENS="$work/tokens.json" BEDROCK_API_TOKEN="$fresh" "$creator" slot-new >/dev/null 2>&1; then
  printf 'error: full token store accepted an unrelated name\n' >&2; exit 1
fi
cmp "$work/before.json" "$work/tokens.json"
BEDROCK_API_TEST_MODE=1 BEDROCK_API_STATE_ROOT="$work" BEDROCK_API_TOKENS="$work/tokens.json" BEDROCK_API_TOKEN="$fresh" "$creator" slot-0 >/dev/null
fresh_hash=$(printf '%s' "$fresh" | sha256sum | awk '{print $1}')
jq -e --arg hash "$fresh_hash" '(.tokens|length)==16 and any(.tokens[]; .name=="slot-0" and .revoked==false and .sha256==$hash)' "$work/tokens.json" >/dev/null
jq -S '[.tokens[]|select(.name!="slot-0")]|sort_by(.name)' "$work/before.json" > "$work/active-before.json"
jq -S '[.tokens[]|select(.name!="slot-0")]|sort_by(.name)' "$work/tokens.json" > "$work/active-after.json"
cmp "$work/active-before.json" "$work/active-after.json"
cp "$work/tokens.json" "$work/recovered.json"
if BEDROCK_API_TEST_MODE=1 BEDROCK_API_STATE_ROOT="$work" BEDROCK_API_TOKENS="$work/tokens.json" "$creator" slot-0 >/dev/null 2>&1; then
  printf 'error: active recovered name was replaced\n' >&2; exit 1
fi
cmp "$work/recovered.json" "$work/tokens.json"
printf 'Bedrock API token tests passed.\n'
