#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool="$ROOT/os/config/includes.chroot/usr/lib/bedrock/start-remote-device-session"
pairing_tool="$ROOT/os/config/includes.chroot/usr/lib/bedrock/start-remote-pairing-session"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
device=42345678-1234-4123-8123-123456789abc
session=52345678-1234-4123-8123-123456789abc
: > "$work/key"
printf '%064d\n' 0 > "$work/api-token"
cat > "$work/systemd-run" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$@" > "$BEDROCK_REMOTE_LAUNCH_LOG"
SCRIPT
chmod +x "$work/systemd-run"
BEDROCK_REMOTE_LAUNCH_TEST_MODE=1 BEDROCK_REMOTE_LAUNCH_SYSTEMD_RUN="$work/systemd-run" \
BEDROCK_REMOTE_LAUNCH_PRIVATE_KEY="$work/key" BEDROCK_REMOTE_LAUNCH_API_TOKEN_FILE="$work/api-token" BEDROCK_REMOTE_LAUNCH_LOG="$work/log" \
  "$tool" "$device" "$session"
grep -Fx -- "--unit=bedrock-remote-session-$device-$session.service" "$work/log" >/dev/null
grep -Fx -- "--property=PartOf=bedrock-remote-device@$device.target" "$work/log" >/dev/null
grep -Fx -- "--property=User=bedrock-remote" "$work/log" >/dev/null
grep -Fx -- "--property=SupplementaryGroups=bedrock-api" "$work/log" >/dev/null
grep -Fx -- "--property=LoadCredential=server-private-key:$work/key" "$work/log" >/dev/null
grep -Fx -- "--property=LoadCredential=api-token:$work/api-token" "$work/log" >/dev/null
grep -Fx -- '--property=Environment=BEDROCK_NOISE_PRIVATE_KEY=%d/server-private-key' "$work/log" >/dev/null
grep -Fx -- '--property=CapabilityBoundingSet=' "$work/log" >/dev/null
grep -Fx -- '--property=RestrictAddressFamilies=AF_UNIX' "$work/log" >/dev/null
grep -Fx -- '--property=RuntimeMaxSec=3600' "$work/log" >/dev/null
grep -Fx -- '--property=MemoryMax=134217728' "$work/log" >/dev/null
grep -Fx -- '--property=TasksMax=16' "$work/log" >/dev/null
tail -n 2 "$work/log" | grep -Fx -- '--require-device' >/dev/null
tail -n 1 "$work/log" | grep -Fx -- "$device" >/dev/null
BEDROCK_REMOTE_LAUNCH_TEST_MODE=1 BEDROCK_REMOTE_LAUNCH_SYSTEMD_RUN="$work/systemd-run" \
BEDROCK_REMOTE_LAUNCH_PRIVATE_KEY="$work/key" BEDROCK_REMOTE_LAUNCH_LOG="$work/pairing-log" \
  "$pairing_tool" "$session"
grep -Fx -- "--unit=bedrock-remote-pairing-$session.service" "$work/pairing-log" >/dev/null
grep -Fx -- '--property=RuntimeMaxSec=30' "$work/pairing-log" >/dev/null
if grep -F -- 'SupplementaryGroups=bedrock-api' "$work/pairing-log" >/dev/null; then
  printf 'error: pairing session received API access\n' >&2; exit 1
fi
if BEDROCK_REMOTE_LAUNCH_TEST_MODE=1 BEDROCK_REMOTE_LAUNCH_SYSTEMD_RUN="$work/systemd-run" BEDROCK_REMOTE_LAUNCH_PRIVATE_KEY="$work/key" BEDROCK_REMOTE_LAUNCH_API_TOKEN_FILE="$work/api-token" "$tool" '../bad' "$session" >/dev/null 2>&1; then
  printf 'error: unsafe device identity was accepted\n' >&2; exit 1
fi
printf 'Remote device session unit-binding tests passed.\n'
