#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner="$ROOT/os/config/includes.chroot/usr/lib/bedrock/run-live-hardware-test"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/efi" "$work/test-run"
printf 'boot=live bedrock.mode=hardware-test\n' > "$work/cmdline"
cat > "$work/bin/collector" <<'EOF'
#!/bin/sh
jq -n '{schema:2,cpu:{architecture:"x86_64",logical_processors:8,virtualization_supported:true},memory:{total_bytes:17179869184},disks:[{size_bytes:68719476736}],networks:[{link_type:"ether"}]}' > "$1"
EOF
chmod +x "$work/bin/collector"
BEDROCK_LIVE_TEST_CMDLINE="$work/cmdline" BEDROCK_LIVE_TEST_COLLECTOR="$work/bin/collector" BEDROCK_LIVE_TEST_RUN_ROOT="$work/test-run" BEDROCK_LIVE_TEST_EFI_ROOT="$work/efi" "$runner" >/dev/null
jq -e '.schema==1 and .mode=="live-hardware-test" and .non_destructive==true and .status=="ready" and all(.checks[];.==true)' "$work/test-run/report.json" >/dev/null
printf 'boot=live\n' > "$work/cmdline"
if BEDROCK_LIVE_TEST_CMDLINE="$work/cmdline" BEDROCK_LIVE_TEST_COLLECTOR="$work/bin/collector" BEDROCK_LIVE_TEST_RUN_ROOT="$work/test-run" BEDROCK_LIVE_TEST_EFI_ROOT="$work/efi" "$runner" >/dev/null 2>&1; then echo 'hardware test ran without explicit boot mode' >&2; exit 1; fi
printf 'Bedrock live hardware-test mode tests passed.\n'
