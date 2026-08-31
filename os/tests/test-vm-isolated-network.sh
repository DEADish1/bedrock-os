#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manager="$ROOT/os/config/includes.chroot/usr/lib/bedrock/manage-isolated-network"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"
jq -n '{schema:1,networks:[]}' > "$work/networks.json"
: > "$work/network-state"; : > "$work/virsh.log"
cat > "$work/bin/virsh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$BEDROCK_VM_TEST_LOG"
case "$3" in
  net-info) grep -q '^defined ' "$BEDROCK_VM_NETWORK_STATE" || exit 1; active=no; autostart=no; grep -q '^active ' "$BEDROCK_VM_NETWORK_STATE" && active=yes; grep -q '^autostart ' "$BEDROCK_VM_NETWORK_STATE" && autostart=yes; printf 'Name: %s\nActive: %s\nAutostart: %s\n' "$4" "$active" "$autostart" ;;
  net-define) printf 'defined %s\n' "$4" > "$BEDROCK_VM_NETWORK_STATE" ;;
  net-start) printf 'active %s\n' "$4" >> "$BEDROCK_VM_NETWORK_STATE" ;;
  net-autostart) printf 'autostart %s\n' "$4" >> "$BEDROCK_VM_NETWORK_STATE" ;;
  net-destroy) sed '/^active /d' "$BEDROCK_VM_NETWORK_STATE" > "$BEDROCK_VM_NETWORK_STATE.tmp"; mv "$BEDROCK_VM_NETWORK_STATE.tmp" "$BEDROCK_VM_NETWORK_STATE" ;;
  net-undefine) : > "$BEDROCK_VM_NETWORK_STATE" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/virsh"
request() { jq -n --arg action "$1" --arg confirmation "$2" '{schema:1,name:"lab",subnet_octet:42,action:$action,confirmation:$confirmation}' > "$work/request.json"; }
run() { BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_NETWORKS="$work/networks.json" BEDROCK_VM_VIRSH="$work/bin/virsh" BEDROCK_VM_TEST_LOG="$work/virsh.log" BEDROCK_VM_NETWORK_STATE="$work/network-state" "$manager" "$work/request.json"; }
request create 'CREATE ISOLATED NETWORK lab 10.240.42.0/24'; run | jq -e '.forwarding==false and .bridge=="br-bedrock-42"' >/dev/null
jq -e '.networks|length==1 and .[0].cidr=="10.240.42.0/24"' "$work/networks.json" >/dev/null
! grep -q '<forward' "$work/state/networks/lab.xml"
request delete 'DELETE ISOLATED NETWORK lab 10.240.42.0/24'; run | jq -e '.action=="delete"' >/dev/null
jq -e '.networks==[]' "$work/networks.json" >/dev/null
[ ! -e "$work/state/networks/lab.xml" ]
must_fail() { if "$@" >/dev/null 2>&1; then printf 'error: command unexpectedly succeeded\n' >&2; exit 1; fi; }
must_fail run
request create 'CREATE ISOLATED NETWORK lab 10.240.43.0/24'; must_fail run
printf 'VM isolated-network tests passed.\n'
