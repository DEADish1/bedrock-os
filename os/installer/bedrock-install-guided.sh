#!/bin/sh
set -eu

if [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ]; then
  PATH=${BEDROCK_TEST_INSTALL_PATH:?test mode requires BEDROCK_TEST_INSTALL_PATH}
else
  PATH=/usr/sbin:/usr/bin:/sbin:/bin
fi
LC_ALL=C
export PATH LC_ALL

if [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ]; then
  scanner=${BEDROCK_TEST_INSTALL_SCANNER:?test mode requires BEDROCK_TEST_INSTALL_SCANNER}
  planner=${BEDROCK_TEST_INSTALL_PLANNER:?test mode requires BEDROCK_TEST_INSTALL_PLANNER}
  request_creator=${BEDROCK_TEST_INSTALL_REQUEST_CREATOR:?test mode requires BEDROCK_TEST_INSTALL_REQUEST_CREATOR}
  writer=${BEDROCK_TEST_INSTALL_WRITER:?test mode requires BEDROCK_TEST_INSTALL_WRITER}
  layout=${BEDROCK_TEST_LAYOUT:?test mode requires BEDROCK_TEST_LAYOUT}
else
  [ "$(id -u)" -eq 0 ] || { printf 'error: guided system installation requires root\n' >&2; exit 1; }
  scanner=/usr/lib/bedrock/installer/linux-list-targets.sh
  planner=/usr/lib/bedrock/installer/create-install-plan.sh
  request_creator=/usr/lib/bedrock/installer/create-protected-install-request.sh
  writer=/usr/sbin/bedrock-install-system
  layout=/usr/share/bedrock/installer/bedrock-amd64.json
  metadata=/usr/share/bedrock/installer/package.json
  [ -f "$metadata" ] && [ ! -L "$metadata" ] &&
    jq -e '.schema == 1 and .writer_enabled == true' "$metadata" >/dev/null || {
    dialog --title 'Installer unavailable' --msgbox \
      'This image was not built as an approved installation-acceptance image. No disk was opened or changed.' 9 72 || true
    exit 1
  }
fi

for tool in dialog jq mktemp; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: guided installation requires %s\n' "$tool" >&2; exit 2; }
done
for component in "$scanner" "$planner" "$request_creator" "$writer" "$layout"; do
  [ -e "$component" ] && [ ! -L "$component" ] || {
    printf 'error: guided installer component is missing or indirect\n' >&2
    exit 1
  }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM
umask 077

cancelled() {
  dialog --title 'Installation cancelled' --msgbox \
    'No installation was started. You can reopen the installer from the local console.' 8 68 || true
  exit 0
}

dialog --title 'Install Bedrock Server OS' --msgbox \
  'This guided installer writes Bedrock to one internal system drive. The live boot media, removable drives, mounted drives, and the running system are protected from selection.' 11 74 || cancelled

"$scanner" > "$work/inventory.json" || {
  dialog --title 'Drive scan failed' --msgbox \
    'Bedrock could not safely identify the live media and installation drives. No disk was opened or changed.' 9 70 || true
  exit 1
}
minimum=$(jq -er '.minimum_disk_bytes | select(type == "number" and floor == . and . > 0)' "$layout") || {
  dialog --title 'Installer unavailable' --msgbox 'The Bedrock disk-layout definition is invalid.' 7 64 || true
  exit 1
}
jq -c --argjson minimum "$minimum" '
  .targets[] |
  select(.system == false and .removable == false and .mounted == false and
         .read_only == false and .size_bytes >= $minimum)
' "$work/inventory.json" > "$work/eligible.jsonl"
[ -s "$work/eligible.jsonl" ] || {
  dialog --title 'No eligible system drive' --msgbox \
    'No unused internal drive of at least 32 GiB is available. Disconnect or unmount data drives only after confirming they are safe to erase.' 10 72 || true
  exit 1
}

set --
while IFS= read -r target; do
  id=$(printf '%s\n' "$target" | jq -r .id)
  description=$(printf '%s\n' "$target" | jq -r '
    "\(.model) | \(.path) | \((.size_bytes / 1073741824 * 10 | floor) / 10) GiB"
  ')
  set -- "$@" "$id" "$description"
done < "$work/eligible.jsonl"
target_id=$(dialog --stdout --title 'Choose the system drive' --menu \
  'Everything on the selected drive will be permanently erased.' 18 90 8 "$@") || cancelled

target=$(jq -c --arg id "$target_id" '.targets[] | select(.id == $id)' "$work/inventory.json")
[ -n "$target" ] || { printf 'error: selected target disappeared from inventory\n' >&2; exit 1; }
expected=$(printf '%s\n' "$target" | jq -r '"INSTALL BEDROCK — \(.model) — \(.path) — \(.size_bytes)"')
typed=$(dialog --stdout --title 'Confirm permanent erase' --inputbox \
  "Type this complete phrase exactly:\n\n$expected" 13 92) || cancelled
if [ "$typed" != "$expected" ]; then
  dialog --title 'Confirmation did not match' --msgbox \
    'The complete drive name, path, and capacity must match exactly. No disk was opened or changed.' 9 72 || true
  exit 1
fi

"$planner" "$work/inventory.json" "$target_id" "$typed" > "$work/plan.json" || {
  dialog --title 'Safety check failed' --msgbox \
    'The selected drive did not pass Bedrock safety checks. No disk was opened or changed.' 9 68 || true
  exit 1
}
review=$(jq -r '
  "Drive: \(.target.model)\nPath: \(.target.path)\nCapacity: \(.target.size_bytes) bytes\nPartitions: \(.layout.partitions | length)\n\nAll existing data on this drive will be permanently erased."
' "$work/plan.json")
dialog --title 'Final installation review' --yesno \
  "$review\n\nStart verified installation now?" 16 78 || cancelled

"$request_creator" "$work/plan.json" > "$work/request.json" || {
  dialog --title 'Installer request failed' --msgbox \
    'Bedrock could not create a short-lived protected installation request. No disk was opened or changed.' 9 72 || true
  exit 1
}
dialog --title 'Installing Bedrock' --infobox \
  'Writing and verifying the system. Do not power off or disconnect either drive.' 7 70
if ! "$writer" "$work/request.json" > "$work/result.json"; then
  dialog --title 'Installation incomplete' --msgbox \
    'Bedrock could not complete and verify the installation. Do not boot this target. Restart the installer and perform a complete rewrite.' 10 74 || true
  exit 1
fi
jq -e '
  .schema == 1 and .installation_complete == true and
  .raw_write_complete == true and .reread_verified == true and
  .layout_finalized == true and .gpt_verified == true and
  .persistent_state_checked == true
' "$work/result.json" >/dev/null || {
  dialog --title 'Installation not verified' --msgbox \
    'The installer did not return complete verification evidence. Do not boot this target; perform a complete rewrite.' 10 74 || true
  exit 1
}

next=$(dialog --stdout --title 'Installation complete' --menu \
  'Bedrock was written, reread, and verified. Remove the installation media before the next boot.' 14 76 3 \
  reboot 'Reboot now' poweroff 'Power off now' return 'Return to the live console') || next=return
case $next in
  reboot) [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ] || systemctl reboot ;;
  poweroff) [ "${BEDROCK_INSTALLER_TEST_MODE:-0}" = 1 ] || systemctl poweroff ;;
  return) : ;;
  *) printf 'error: invalid completion action\n' >&2; exit 1 ;;
esac
