#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
issuer="$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-vm-console-session"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
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
jq -n '{schema:1,vm:"test-vm",confirmation:"OPEN CONSOLE VM test-vm"}' > "$work/request.json"
token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_DOMAINS="$work/domains.json" BEDROCK_VM_CONSOLE_SESSIONS="$work/sessions.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_NOW=1788148800 BEDROCK_VM_CONSOLE_TOKEN="$token" "$issuer" "$work/request.json"; }
run | jq -e --arg token "$token" '.status=="authorized" and .token==$token and .one_time==true and .expires_at==1788148860' >/dev/null
token_hash=$(printf '%s' "$token" | sha256sum | awk '{print $1}')
expected_socket=$(jq -nr --arg socket '/run/libvirt/qemu/bedrock-test-vm.vnc' '$socket' | tr -d '\r')
jq -e --arg hash "$token_hash" --arg socket "$expected_socket" '.sessions|length==1 and .[0].token_sha256==$hash and .[0].used==false and .[0].socket==$socket' "$work/sessions.json" >/dev/null || { cat "$work/sessions.json" >&2; exit 1; }
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
MOCK_VM_STATE='shut off' must_fail run
jq '.confirmation="OPEN CONSOLE VM wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"; must_fail run
printf 'VM console session tests passed.\n'
