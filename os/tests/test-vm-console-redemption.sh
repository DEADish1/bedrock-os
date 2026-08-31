#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
issuer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-vm-console-session"
redeemer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/redeem-vm-console-session"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"; : > "$work/socket"
jq -n '{schema:1,domains:[{name:"test-vm"}]}' > "$work/domains.json"
jq -n '{schema:1,sessions:[]}' > "$work/sessions.json"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
case "$3" in
  domstate) printf '%s\n' "${MOCK_VM_STATE:-running}" ;;
  dumpxml) printf "%s\n" "<domain><devices><graphics type='vnc' autoport='no' socket='/run/libvirt/qemu/bedrock-test-vm.vnc' sharePolicy='ignore'/></devices></domain>" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$work/bin/virsh"
token=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
jq -n '{schema:1,vm:"test-vm",confirmation:"OPEN CONSOLE VM test-vm"}' > "$work/issue.json"
common="BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT=$work/state BEDROCK_VM_CONSOLE_SESSIONS=$work/sessions.json BEDROCK_VM_VIRSH=$work/bin/virsh BEDROCK_VM_NOW=1788148800"
env $common BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_CONSOLE_TOKEN="$token" "$issuer" "$work/issue.json" >/dev/null
jq -n --arg token "$token" '{schema:1,vm:"test-vm",token:$token}' > "$work/redeem.json"
run() { env $common BEDROCK_VM_TEST_CONSOLE_SOCKET="$work/socket" "$redeemer" "$work/redeem.json"; }
run_expired() { env $common BEDROCK_VM_NOW=1788148861 BEDROCK_VM_TEST_CONSOLE_SOCKET="$work/socket" "$redeemer" "$work/redeem.json"; }
run | jq -e '.status=="redeemed" and .one_time==true and .network_listener==false' >/dev/null
jq -e '.sessions|length==1 and .[0].used==true' "$work/sessions.json" >/dev/null
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail run
env $common BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_CONSOLE_TOKEN="$token" "$issuer" "$work/issue.json" >/dev/null
must_fail run_expired
jq '.token="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"' "$work/redeem.json" > "$work/bad.json"; mv "$work/bad.json" "$work/redeem.json"; must_fail run
printf 'VM console redemption tests passed.\n'
