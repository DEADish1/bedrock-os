#!/bin/sh
set -eu

command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 2; }

if [ -n "${BEDROCK_MACOS_DISKS_JSON:-}" ]; then
  source_json=$BEDROCK_MACOS_DISKS_JSON
else
  command -v diskutil >/dev/null 2>&1 || { printf 'error: diskutil is required\n' >&2; exit 2; }
  command -v plutil >/dev/null 2>&1 || { printf 'error: plutil is required\n' >&2; exit 2; }
  list_json=$(diskutil list -plist | plutil -convert json -o - -)
  root_parent=$(diskutil info -plist / | plutil -convert json -o - - | jq -r '.ParentWholeDisk // ""')
  disks='[]'
  for name in $(printf '%s\n' "$list_json" | jq -r '.WholeDisks[]'); do
    info=$(diskutil info -plist "/dev/$name" | plutil -convert json -o - -)
    mounted=false
    for partition in $(printf '%s\n' "$list_json" | jq -r --arg name "$name" \
      '.AllDisksAndPartitions[] | select(.DeviceIdentifier == $name) | .Partitions[]?.DeviceIdentifier'); do
      mount_point=$(diskutil info -plist "/dev/$partition" | plutil -convert json -o - - | jq -r '.MountPoint // ""')
      [ -z "$mount_point" ] || mounted=true
    done
    disk=$(printf '%s\n' "$info" | jq -c --argjson mounted "$mounted" '{
      name: .DeviceIdentifier,
      path: ("/dev/" + .DeviceIdentifier),
      model: ((.MediaName // .DeviceModel // "Unknown removable drive") | if length == 0 then "Unknown removable drive" else . end),
      size_bytes: .TotalSize,
      removable: ((.RemovableMedia // false) or (.Ejectable // false)),
      read_only: (.ReadOnlyMedia // false),
      mounted: $mounted
    }')
    disks=$(jq -cn --argjson current "$disks" --argjson disk "$disk" '$current + [$disk]')
  done
  source_json=$(jq -cn --arg root_parent "$root_parent" --argjson disks "$disks" \
    '{root_parent: $root_parent, disks: $disks}')
fi

generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
printf '%s\n' "$source_json" | jq -c --arg generated_at "$generated_at" '
  {
    schema: 1,
    generated_at: $generated_at,
    targets: [
      . as $source | .disks[] |
      {
        id: ("macos:" + ([.path, .model, (.size_bytes | tostring)] | join("|") | @base64)),
        path,
        model,
        size_bytes,
        removable,
        system: (if ($source.root_parent // "") == "" then true else .name == $source.root_parent end),
        mounted,
        read_only
      }
    ]
  }
'
