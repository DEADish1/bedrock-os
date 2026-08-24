#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
validator="$ROOT/os/config/includes.chroot/usr/lib/bedrock/validate-first-run-config"
applier="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-apply-first-run"
wizard="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-first-run"
fixture="$ROOT/os/tests/fixtures/first-run"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/zoneinfo/America"
: > "$work/zoneinfo/America/New_York"
password_hash='$6$testsalt1234567$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

jq -n --arg hash "$password_hash" '{
  schema:1,hostname:"bedrock-home",
  administrator:{username:"admin",display_name:"Bedrock Administrator",password_hash:$hash},
  network:{interface:"enp1s0",mode:"dhcp",address_cidr:null,gateway:null,dns:["1.1.1.1"]},
  time:{timezone:"America/New_York",ntp:true},updates:{automatic_checks:true}
}' > "$work/dhcp.json"

run_validator() {
  BEDROCK_FIRST_RUN_TEST_MODE=1 BEDROCK_FIRST_RUN_TIMEZONE_ROOT="$work/zoneinfo" \
  BEDROCK_FIRST_RUN_TEST_NOW=1787616000 "$validator" "$1"
}
run_validator "$work/dhcp.json" > "$work/plan.json"
jq -e '
  .schema == 1 and .operation == "apply-first-run-configuration" and
  .hostname == "bedrock-home" and .administrator.username == "admin" and
  .administrator.password_configured == true and .secrets_included == false and
  (tostring | contains("testsalt") | not) and
  .network.mode == "dhcp" and .time.timezone == "America/New_York" and
  .updates.automatic_checks == true and .ready_to_apply == true
' "$work/plan.json" >/dev/null

jq '.network = {interface:"enp1s0",mode:"static",address_cidr:"192.168.50.10/24",gateway:"192.168.50.1",dns:["192.168.50.1","1.1.1.1"]}' \
  "$work/dhcp.json" > "$work/static.json"
run_validator "$work/static.json" | jq -e '
  .network.mode == "static" and .network.address_cidr == "192.168.50.10/24" and
  (.network.dns | length) == 2
' >/dev/null

reject() {
  label=$1 file=$2
  if run_validator "$file" >/dev/null 2>&1; then
    printf 'error: first-run validator accepted %s\n' "$label" >&2
    exit 1
  fi
}
jq '.hostname = "Bad Host"' "$work/dhcp.json" > "$work/bad-host.json"
reject invalid-hostname "$work/bad-host.json"
jq '.administrator.username = "root"' "$work/dhcp.json" > "$work/root.json"
reject reserved-administrator "$work/root.json"
jq '.administrator.password_hash = "plaintext"' "$work/dhcp.json" > "$work/plaintext.json"
reject plaintext-password "$work/plaintext.json"
jq '.network.interface = "lo"' "$work/dhcp.json" > "$work/loopback.json"
reject loopback-interface "$work/loopback.json"
jq '.network = {interface:"enp1s0",mode:"static",address_cidr:"192.168.1.300/24",gateway:"192.168.1.1",dns:[]}' \
  "$work/dhcp.json" > "$work/bad-address.json"
reject invalid-static-address "$work/bad-address.json"
jq '.network.dns = ["999.1.1.1"]' "$work/dhcp.json" > "$work/bad-dns.json"
reject invalid-dns "$work/bad-dns.json"
jq '.time.timezone = "../etc/passwd"' "$work/dhcp.json" > "$work/traversal.json"
reject timezone-traversal "$work/traversal.json"
jq '.time.timezone = "Missing/Zone"' "$work/dhcp.json" > "$work/missing-zone.json"
reject unavailable-timezone "$work/missing-zone.json"
ln -s "$work/dhcp.json" "$work/indirect.json"
reject symbolic-link-config "$work/indirect.json"

mkdir -p "$work/root/etc/NetworkManager/system-connections" "$work/root/var/lib/bedrock/setup" \
  "$work/sys/class/net/enp1s0" "$work/commands"
: > "$work/commands.log"
for command in chpasswd getent hostnamectl nmcli timedatectl useradd userdel; do
  ln -s "$fixture/bin/bedrock-command-stub" "$work/commands/$command"
done
run_applier() {
  BEDROCK_FIRST_RUN_TEST_MODE=1 BEDROCK_FIRST_RUN_TEST_ROOT="$1" \
  BEDROCK_FIRST_RUN_TEST_SYS_ROOT="$work/sys" BEDROCK_FIRST_RUN_TIMEZONE_ROOT="$work/zoneinfo" \
  BEDROCK_FIRST_RUN_TEST_PATH="$work/commands" BEDROCK_FIRST_RUN_VALIDATOR="$validator" \
  BEDROCK_FIRST_RUN_UPDATE_SETTINGS="$fixture/bedrock-update-settings" \
  BEDROCK_FIRST_RUN_TEST_LOG="$work/commands.log" BEDROCK_FIRST_RUN_TEST_NOW=1787616000 \
    "$applier" "$2"
}
run_applier "$work/root" "$work/static.json" > "$work/applied.json"
jq -e '
  .setup_complete == true and .secrets_included == false and .administrator.username == "admin" and
  .network.mode == "static" and .updates.automatic_checks == true
' "$work/applied.json" >/dev/null
[ "$(stat -f %Lp "$work/root/var/lib/bedrock/setup/complete.json" 2>/dev/null || stat -c %a "$work/root/var/lib/bedrock/setup/complete.json")" = 600 ]
[ "$(stat -f %Lp "$work/root/etc/NetworkManager/system-connections/bedrock-setup.nmconnection" 2>/dev/null || stat -c %a "$work/root/etc/NetworkManager/system-connections/bedrock-setup.nmconnection")" = 600 ]
grep -q '^address1=192.168.50.10/24,192.168.50.1$' "$work/root/etc/NetworkManager/system-connections/bedrock-setup.nmconnection"
grep -q '^dns=192.168.50.1;1.1.1.1;$' "$work/root/etc/NetworkManager/system-connections/bedrock-setup.nmconnection"
grep -q '^useradd ' "$work/commands.log"
grep -q '^chpasswd admin \[REDACTED\]$' "$work/commands.log"
grep -q '^nmcli connection up bedrock-setup ifname enp1s0$' "$work/commands.log"
if grep -R -q 'testsalt1234567' "$work/root" "$work/commands.log"; then
  printf 'error: applied first-run state retained password material\n' >&2
  exit 1
fi
if run_applier "$work/root" "$work/static.json" >/dev/null 2>&1; then
  printf 'error: first-run setup was applied twice\n' >&2
  exit 1
fi

mkdir -p "$work/failing-root/etc/NetworkManager/system-connections" "$work/failing-root/var/lib/bedrock/setup"
: > "$work/rollback.log"
if BEDROCK_FIRST_RUN_TEST_MODE=1 BEDROCK_FIRST_RUN_TEST_ROOT="$work/failing-root" \
  BEDROCK_FIRST_RUN_TEST_SYS_ROOT="$work/sys" BEDROCK_FIRST_RUN_TIMEZONE_ROOT="$work/zoneinfo" \
  BEDROCK_FIRST_RUN_TEST_PATH="$work/commands" BEDROCK_FIRST_RUN_VALIDATOR="$validator" \
  BEDROCK_FIRST_RUN_UPDATE_SETTINGS="$fixture/bedrock-update-settings" \
  BEDROCK_FIRST_RUN_TEST_LOG="$work/rollback.log" BEDROCK_FIRST_RUN_TEST_FAIL_COMMAND=nmcli-up \
  "$applier" "$work/static.json" >/dev/null 2>&1; then
  printf 'error: first-run setup ignored a network activation failure\n' >&2
  exit 1
fi
[ ! -e "$work/failing-root/var/lib/bedrock/setup/complete.json" ]
[ ! -e "$work/failing-root/etc/NetworkManager/system-connections/bedrock-setup.nmconnection" ]
grep -q '^userdel --remove admin$' "$work/rollback.log"
grep -q '^hostnamectl set-hostname old-host$' "$work/rollback.log"

sh -n "$wizard"
grep -q 'passwordbox' "$wizard"
grep -q 'validate-first-run-config' "$wizard"
grep -q 'bedrock-apply-first-run' "$wizard"
grep -q '^ExecStart=/usr/sbin/bedrock-first-run$' \
  "$ROOT/os/config/includes.chroot/usr/lib/systemd/system/bedrock-first-run.service"
first_run_link="$ROOT/os/config/includes.chroot/etc/systemd/system/multi-user.target.wants/bedrock-first-run.service"
[ -L "$first_run_link" ] &&
  [ "$(readlink "$first_run_link")" = '../../../../usr/lib/systemd/system/bedrock-first-run.service' ] || {
  printf 'error: guided first-run service is not enabled correctly\n' >&2
  exit 1
}

printf 'Bedrock first-run hostname, administrator, network, time, and update configuration tests passed.\n'
