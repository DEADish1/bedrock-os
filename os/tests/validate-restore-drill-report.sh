#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { printf 'usage: %s REPORT.json\n' "$0" >&2; exit 2; }
report=$1
[ -f "$report" ] && [ ! -L "$report" ] || { printf 'error: report must be a regular file\n' >&2; exit 1; }
[ "$(wc -c < "$report")" -le 65536 ] || { printf 'error: report is too large\n' >&2; exit 1; }

jq -e '
  def text: type == "string" and length > 0 and length <= 200;
  def sha: type == "string" and test("^[a-f0-9]{64}$");
  (keys | sort) == (["bedrock_version","completed_at_utc","operator","scenarios","schema"] | sort) and
  .schema == 1 and (.bedrock_version|text) and
  (.completed_at_utc|type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  (.operator|text) and
  (.scenarios|keys|sort) == (["configuration","failed_system_drive","files","vm_data"]|sort) and
  (.scenarios.files|keys|sort) == (["original_sha256","overwrite_prevented","restored_sha256","status"]|sort) and
  .scenarios.files.status == "passed" and
  (.scenarios.files.original_sha256|sha) and
  (.scenarios.files.restored_sha256|sha) and
  .scenarios.files.original_sha256 == .scenarios.files.restored_sha256 and
  .scenarios.files.overwrite_prevented == true and
  (.scenarios.vm_data|keys|sort) == (["baseline_sha256","guest_booted","restored_sha256","snapshot_restore_verified","status"]|sort) and
  .scenarios.vm_data.status == "passed" and
  (.scenarios.vm_data.baseline_sha256|sha) and
  (.scenarios.vm_data.restored_sha256|sha) and
  .scenarios.vm_data.baseline_sha256 == .scenarios.vm_data.restored_sha256 and
  .scenarios.vm_data.guest_booted == true and .scenarios.vm_data.snapshot_restore_verified == true and
  (.scenarios.configuration|keys|sort) == (["archive_sha256","reboot_verified","recovery_copy_retained","secrets_rotated","status"]|sort) and
  .scenarios.configuration.status == "passed" and
  (.scenarios.configuration.archive_sha256|sha) and
  .scenarios.configuration.reboot_verified == true and
  .scenarios.configuration.recovery_copy_retained == true and
  .scenarios.configuration.secrets_rotated == true and
  (.scenarios.failed_system_drive|keys|sort) == (["clean_install_verified","original_drive_untouched","pool_imported_without_creation","replacement_drive_id","shares_verified","status","vms_verified"]|sort) and
  .scenarios.failed_system_drive.status == "passed" and
  (.scenarios.failed_system_drive.replacement_drive_id|text) and
  .scenarios.failed_system_drive.clean_install_verified == true and
  .scenarios.failed_system_drive.original_drive_untouched == true and
  .scenarios.failed_system_drive.pool_imported_without_creation == true and
  .scenarios.failed_system_drive.shares_verified == true and
  .scenarios.failed_system_drive.vms_verified == true
' "$report" >/dev/null || { printf 'error: restore drill evidence is incomplete or invalid\n' >&2; exit 1; }

printf 'Bedrock full restore drill report is valid.\n'
