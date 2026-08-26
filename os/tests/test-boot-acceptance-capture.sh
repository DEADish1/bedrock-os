#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
capture="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-boot-acceptance"
validator="$ROOT/os/tests/validate-boot-test-report.sh"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
root=$work/root; state=$work/session.json; mkdir -p "$root/var/lib/bedrock/hardware" "$root/var/lib/bedrock/boot-health" "$root/proc/sys/kernel/random" "$root/sys/firmware/efi/efivars" "$root/sys/class/dmi/id"
boot_a=123e4567-e89b-42d3-a456-426614174000; boot_b=223e4567-e89b-42d3-a456-426614174000; sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf '\006\000\000\000\000' > "$root/sys/firmware/efi/efivars/SecureBoot-test"
jq -n '{schema:2,cpu:{architecture:"x86_64",model:"Intel Test CPU"},memory:{total_bytes:8589934592},disks:[{}],networks:[{}]}' > "$root/var/lib/bedrock/hardware/inventory.json"
jq -n --arg boot "$boot_a" '{schema:1,slot:"a",boot_id:$boot,healthy:true}' > "$root/var/lib/bedrock/boot-health/last-good.json"
printf '%s\n' "$boot_a" > "$root/proc/sys/kernel/random/boot_id"
printf '%s\n' 'VMware, Inc.' > "$root/sys/class/dmi/id/sys_vendor"; printf '%s\n' 'VMware Virtual Platform' > "$root/sys/class/dmi/id/product_name"
run() {
  test_now=$1; shift
  BEDROCK_BOOT_ACCEPTANCE_TEST_MODE=1 BEDROCK_BOOT_ACCEPTANCE_TEST_ROOT="$root" \
  BEDROCK_BOOT_ACCEPTANCE_TEST_STATE="$state" BEDROCK_BOOT_ACCEPTANCE_TEST_NOW="$test_now" "$capture" "$@"
}
run 2026-08-26T20:00:00Z prepare vmware "$sha" >/dev/null
if run 2026-08-26T20:01:00Z complete "$work/too-early.json" >/dev/null 2>&1; then printf 'error: boot acceptance completed without a reboot\n' >&2; exit 1; fi
printf '%s\n' "$boot_b" > "$root/proc/sys/kernel/random/boot_id"
jq -n --arg boot "$boot_b" '{schema:1,slot:"a",boot_id:$boot,healthy:true}' > "$root/var/lib/bedrock/boot-health/last-good.json"
run 2026-08-26T20:02:00Z complete "$work/vmware.json" >/dev/null
sh "$validator" "$work/vmware.json" >/dev/null
jq -e '.mode=="physical" and .platform=="vmware" and .persistent_reboot==true and .privacy_reviewed==true' "$work/vmware.json" >/dev/null
printf '%s\n' 'Microsoft Corporation' > "$root/sys/class/dmi/id/sys_vendor"; printf '%s\n' 'Virtual Machine' > "$root/sys/class/dmi/id/product_name"
run 2026-08-26T20:03:00Z prepare hyper-v "$sha" >/dev/null
jq -e '.platform_generation=="generation-2"' "$state" >/dev/null
printf '%s\n' 'Physical Vendor' > "$root/sys/class/dmi/id/sys_vendor"; printf '%s\n' 'Rack Server' > "$root/sys/class/dmi/id/product_name"
run 2026-08-26T20:04:00Z prepare physical "$sha" >/dev/null
printf '%s\n' 'VMware, Inc.' > "$root/sys/class/dmi/id/sys_vendor"
if run 2026-08-26T20:05:00Z prepare physical "$sha" >/dev/null 2>&1; then printf 'error: physical capture accepted virtual DMI\n' >&2; exit 1; fi
ln -s "$work/elsewhere.json" "$work/indirect.json"
if run 2026-08-26T20:06:00Z complete "$work/indirect.json" >/dev/null 2>&1; then printf 'error: boot capture accepted indirect output\n' >&2; exit 1; fi
printf 'Bedrock two-boot privacy-safe acceptance capture tests passed.\n'
