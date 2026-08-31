#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
proxy="$ROOT/os/config/includes.chroot/usr/lib/bedrock/start-vm-console-proxy"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin"; : > "$work/socket"
cat > "$work/bin/websockify" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$MOCK_WEBSOCKIFY_ARGS"
EOF
chmod +x "$work/bin/websockify"
make_handoff() { jq -S -n '{schema:1,status:"redeemed",vm:"test-vm",socket:"/run/libvirt/qemu/bedrock-test-vm.vnc",redeemed_at:1788148800,proxy_start_expires_at:1788148810,one_time:true,network_listener:false}' > "$work/handoff.json"; }
run() { PATH="$work/bin:$PATH" MOCK_WEBSOCKIFY_ARGS="$work/args" BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_NOW=1788148805 BEDROCK_VM_HANDOFF_PATH="$work/handoff.json" BEDROCK_VM_TEST_CONSOLE_SOCKET="$work/socket" "$proxy" "$work/handoff.json" 20042; }
make_handoff; run
[ ! -e "$work/handoff.json" ]
grep -Fx -- '--run-once' "$work/args" >/dev/null
grep -Fx -- '--timeout=15' "$work/args" >/dev/null
grep -Fx -- '--idle-timeout=300' "$work/args" >/dev/null
grep -Fx -- '--unix-target=/run/libvirt/qemu/bedrock-test-vm.vnc' "$work/args" >/dev/null
grep -Fx -- '127.0.0.1:20042' "$work/args" >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
make_handoff
expired() { PATH="$work/bin:$PATH" MOCK_WEBSOCKIFY_ARGS="$work/args" BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_NOW=1788148811 BEDROCK_VM_HANDOFF_PATH="$work/handoff.json" BEDROCK_VM_TEST_CONSOLE_SOCKET="$work/socket" "$proxy" "$work/handoff.json" 20042; }
must_fail expired
make_handoff
must_fail env PATH="$work/bin:$PATH" MOCK_WEBSOCKIFY_ARGS="$work/args" BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_NOW=1788148805 BEDROCK_VM_HANDOFF_PATH="$work/handoff.json" BEDROCK_VM_TEST_CONSOLE_SOCKET="$work/socket" "$proxy" "$work/handoff.json" 19999
make_handoff; jq '.network_listener=true' "$work/handoff.json" > "$work/bad.json"; mv "$work/bad.json" "$work/handoff.json"; must_fail run
printf 'VM console proxy tests passed.\n'
