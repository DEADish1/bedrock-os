#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
policy="$ROOT/os/config/includes.chroot/usr/share/bedrock/guest-compatibility.json"
guide="$ROOT/docs/GUEST-COMPATIBILITY.md"
jq -e '
  (keys|sort)==(["macos","schema","windows"]|sort) and .schema==1 and
  .windows.architecture=="x86_64" and .windows.status=="blocked-pending-acceptance" and
  .windows.driver_media=="user-supplied-signed-virtio-win" and .windows.secure_boot_required==true and .windows.tpm2_required==true and
  .macos.status=="unsupported" and .macos.non_apple_hardware=="blocked" and
  .macos.apple_silicon_host=="unsupported-architecture" and .macos.intel_apple_host=="no-support-claim" and .macos.images_distributed==false
' "$policy" >/dev/null
for text in viostor NetKVM 'Windows 11 must not be labeled supported' 'macOS guests are unsupported' 'non-Apple hardware' 'not legal advice'; do
  grep -F "$text" "$guide" >/dev/null || { printf 'error: guest guide is missing required guidance: %s\n' "$text" >&2; exit 1; }
done
printf 'Guest compatibility policy tests passed.\n'
