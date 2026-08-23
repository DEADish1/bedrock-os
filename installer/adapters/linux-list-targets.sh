#!/bin/sh
set -eu

command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }

if [ -n "${BEDROCK_LSBLK_JSON:-}" ]; then
  inventory=$BEDROCK_LSBLK_JSON
else
  command -v lsblk >/dev/null 2>&1 || { printf 'error: lsblk is required\n' >&2; exit 2; }
  inventory=$(lsblk --bytes --json --output NAME,PATH,TYPE,SIZE,MODEL,RM,RO,MOUNTPOINTS,PKNAME)
fi

if [ -n "${BEDROCK_ROOT_PARENT:-}" ]; then
  root_parent=$BEDROCK_ROOT_PARENT
else
  root_parent=$(printf '%s\n' "$inventory" | jq -r '
    [.blockdevices[] | .. | objects |
      select((.mountpoints // []) | index("/") != null) |
      (.pkname // (if .type == "disk" then .name else empty end))][0] // ""
  ')
fi

generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
printf '%s\n' "$inventory" | jq -c \
  --arg generated_at "$generated_at" \
  --arg root_parent "$root_parent" '
  {
    schema: 1,
    generated_at: $generated_at,
    targets: [
      .blockdevices[] |
      select(.type == "disk") |
      {
        source_name: .name,
        path: .path,
        model: ((.model // "Unknown removable drive") | gsub("^\\s+|\\s+$"; "")),
        size_bytes: (.size | tonumber),
        removable: ((.rm | tonumber) == 1),
        system: (if $root_parent == "" then true else .name == $root_parent end),
        mounted: ([.. | objects | .mountpoints? // [] | .[]?] | any(. != null)),
        read_only: ((.ro | tonumber) == 1)
      }
    ]
  } |
  .targets |= map(
    .id = ("linux:" + ([.path, .model, (.size_bytes | tostring)] | join("|") | @base64)) |
    del(.source_name)
  )
'
