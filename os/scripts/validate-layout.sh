#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
LAYOUT="$ROOT/os/layout/bedrock-amd64.json"

command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 1; }
[ -s "$LAYOUT" ] || { printf 'error: layout file is missing\n' >&2; exit 1; }

jq -e '
  .schema == 1 and
  .architecture == "amd64" and
  .firmware == "uefi" and
  .minimum_disk_bytes >= 34359738368 and
  .boot_policy.active_slot == "a" and
  .boot_policy.attempts_before_rollback == 3 and
  .boot_policy.promotion_requires_health == true and
  (.partitions | length) == 8 and
  ([.partitions[].number] == [1,2,3,4,5,6,7,8]) and
  ([.partitions[].name] | unique | length) == 8 and
  ([.partitions[].role] == ["efi-system","root-a","verity-a","verity-signature-a","root-b","verity-b","verity-signature-b","persistent-state"]) and
  (.partitions[0].type_guid == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b") and
  (.partitions[1].type_guid == "4f68bce3-e8cd-4db1-96e7-fbcaf984b709") and
  (.partitions[2].type_guid == "2c7357ed-ebd2-46d9-aec1-23d437ec2bf5") and
  (.partitions[3].type_guid == "41092b05-9fc8-4523-994f-2def0408b176") and
  (.partitions[4].type_guid == .partitions[1].type_guid) and
  (.partitions[5].type_guid == .partitions[2].type_guid) and
  (.partitions[6].type_guid == .partitions[3].type_guid) and
  (.partitions[1].mutable == false and .partitions[4].mutable == false) and
  (.partitions[7].grow == true and .partitions[7].mutable == true)
' "$LAYOUT" >/dev/null

fixed=$(jq '[.partitions[] | .size_bytes // .minimum_size_bytes] | add' "$LAYOUT")
minimum=$(jq '.minimum_disk_bytes' "$LAYOUT")
[ "$fixed" -lt "$minimum" ] || { printf 'error: partitions leave no installation workspace\n' >&2; exit 1; }

printf 'Bedrock A/B disk layout is valid (%s bytes reserved, %s byte minimum disk).\n' "$fixed" "$minimum"

