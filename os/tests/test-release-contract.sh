#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
contract="$root/release/1.0-contract.json"
openapi="$root/os/config/includes.chroot/usr/share/bedrock/api/openapi-v1.json"

jq -e '
  (keys|sort)==(["api","deferred","frozen_at_utc","host","in_scope","migration","release","schema"]|sort) and
  .schema==1 and .release=="1.0.0" and
  (.frozen_at_utc|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  .host=={"architecture":"amd64","distribution":"trixie","firmware":"uefi","secure_boot_required":true,"minimum_threads":4,"minimum_memory_gib":8,"minimum_system_drive_gib":32,"primary_network":"wired-ethernet"} and
  .api.major=="v1" and .api.compatibility=="additive-only" and (.api.paths|length)>0 and (.api.paths|sort|unique)==.api.paths and
  .migration.minimum_source=="0.2.0" and .migration.forward_only==true and .migration.backup_before_mutation==true and .migration.atomic_commit==true and .migration.failed_migration_blocks_promotion==true and .migration.downgrade_uses_previous_slot_and_state_backup==true and
  (.in_scope|length)==9 and (.in_scope|unique|length)==9 and (.deferred|length)==8 and (.deferred|unique|length)==8
' "$contract" >/dev/null || { printf 'error: 1.0 contract is invalid\n' >&2; exit 1; }

jq -e --slurpfile contract "$contract" '(.paths|keys|sort)==$contract[0].api.paths and .info.version=="1.0.0"' "$openapi" >/dev/null || { printf 'error: OpenAPI drifted from the frozen contract\n' >&2; exit 1; }
grep -q '^BEDROCK_DISTRIBUTION=trixie$' "$root/os/build.env"
grep -q '^BEDROCK_ARCHITECTURE=amd64$' "$root/os/build.env"
grep -q 'Architecture: 64-bit Intel/AMD' "$root/docs/HARDWARE-SUPPORT.md"
grep -q 'Firmware: UEFI boot required' "$root/docs/HARDWARE-SUPPORT.md"
grep -q 'System drive: dedicated 32 GB minimum' "$root/docs/HARDWARE-SUPPORT.md"

printf 'Bedrock 1.0 scope, API, migration, and hardware contract tests passed.\n'
