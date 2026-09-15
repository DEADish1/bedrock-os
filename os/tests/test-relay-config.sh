#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool="$ROOT/os/config/includes.chroot/usr/lib/bedrock/configure-remote-relay"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/systemctl" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_RELAY_TEST_LOG"
SCRIPT
chmod +x "$work/systemctl"
route=42345678-1234-4123-8123-123456789abc
token=abcdefghijklmnopqrstuvwxyz_ABCDEFGHIJKLMNOPQRSTUVWXYZ-0123456789
jq -n --arg route "$route" --arg token "$token" '{schema:1,operation:"configure",host:"relay.bedrock.test",port:443,server_route:$route,token:$token,confirmation:("CONFIGURE REMOTE RELAY relay.bedrock.test:443 ROUTE "+$route)}' > "$work/request.json"
env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" BEDROCK_RELAY_TEST_LOG="$work/systemctl.log" "$tool" "$work/request.json" | jq -e '.status=="configured" and .credentials_exposed==false' >/dev/null
jq -e --arg route "$route" '.schema==1 and .host=="relay.bedrock.test" and .port==443 and .server_route==$route and .connect_timeout_seconds==10 and .idle_timeout_seconds==90 and (has("token")|not)' "$work/state/relay.json" >/dev/null
[ "$(tr -d '\n' < "$work/state/relay-token")" = "$token" ]
[ "$(stat -c %a "$work/state/relay.json")" = 600 ] && [ "$(stat -c %a "$work/state/relay-token")" = 600 ]
if grep -R -F "$token" "$work/systemctl.log" "$work/state/relay.json" >/dev/null; then printf 'error: relay credential escaped its credential file\n' >&2; exit 1; fi
grep -Fx 'restart bedrock-relay-connector.service' "$work/systemctl.log" >/dev/null
jq -n '{schema:1,operation:"disable",confirmation:"DISABLE REMOTE RELAY"}' > "$work/disable.json"
env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" BEDROCK_RELAY_TEST_LOG="$work/systemctl.log" "$tool" "$work/disable.json" | jq -e '.status=="disabled" and .credentials_removed==true' >/dev/null
[ ! -e "$work/state/relay.json" ] && [ ! -e "$work/state/relay-token" ]
grep -Fx 'stop bedrock-relay-connector.service' "$work/systemctl.log" >/dev/null
jq '.confirmation="wrong"' "$work/request.json" > "$work/bad.json"
if env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" "$tool" "$work/bad.json" >/dev/null 2>&1; then printf 'error: bad relay confirmation was accepted\n' >&2; exit 1; fi
ln -s "$work/request.json" "$work/indirect.json"
if env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" "$tool" "$work/indirect.json" >/dev/null 2>&1; then printf 'error: indirect relay request was accepted\n' >&2; exit 1; fi
printf 'Guarded remote relay configuration tests passed.\n'
