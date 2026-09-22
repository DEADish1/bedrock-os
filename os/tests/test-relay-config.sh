#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool="$ROOT/os/config/includes.chroot/usr/lib/bedrock/configure-remote-relay"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export BEDROCK_API_TASK_TEST_MODE=1 BEDROCK_API_TASK_STATE_DIR="$work/api"
cat > "$work/systemctl" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_RELAY_TEST_LOG"
SCRIPT
chmod +x "$work/systemctl"
route=42345678-1234-4123-8123-123456789abc
token=abcdefghijklmnopqrstuvwxyz_ABCDEFGHIJKLMNOPQRSTUVWXYZ-0123456789
jq -n --arg route "$route" --arg token "$token" '{schema:1,operation:"configure",host:"relay.bedrock.test",port:443,server_route:$route,token:$token,confirmation:("CONFIGURE REMOTE RELAY relay.bedrock.test:443 ROUTE "+$route)}' > "$work/request.json"
mkdir "$work/public"
env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" BEDROCK_RELAY_PUBLIC_STATUS="$work/public/relay.json" BEDROCK_RELAY_TEST_LOG="$work/systemctl.log" "$tool" "$work/request.json" | jq -e '.status=="configured" and .credentials_exposed==false' >/dev/null
jq -e --arg route "$route" '.schema==1 and .host=="relay.bedrock.test" and .port==443 and .server_route==$route and .connect_timeout_seconds==10 and .idle_timeout_seconds==90 and (has("token")|not)' "$work/state/relay.json" >/dev/null
[ "$(tr -d '\n' < "$work/state/relay-token")" = "$token" ]
[ "$(stat -c %a "$work/state/relay.json")" = 600 ] && [ "$(stat -c %a "$work/state/relay-token")" = 600 ]
if grep -R -F "$token" "$work/systemctl.log" "$work/state/relay.json" >/dev/null; then printf 'error: relay credential escaped its credential file\n' >&2; exit 1; fi
grep -Fx 'restart bedrock-relay-connector.service' "$work/systemctl.log" >/dev/null
jq -e '.schema==1 and .configured==true' "$work/public/relay.json" >/dev/null
jq -e '[.tasks[] | select(.kind=="remote-relay-configure" and .state=="succeeded")] | length==1' "$work/api/tasks.json" >/dev/null
cat > "$work/failing-systemctl" <<'SCRIPT'
#!/bin/sh
[ "$1" != restart ]
SCRIPT
chmod +x "$work/failing-systemctl"
jq '.token="newsecretnewsecretnewsecretnewsecret"' "$work/request.json" > "$work/changed.json"
if env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/failing-systemctl" BEDROCK_RELAY_PUBLIC_STATUS="$work/public/relay.json" "$tool" "$work/changed.json" >/dev/null 2>&1; then printf 'error: failed restart was accepted\n' >&2; exit 1; fi
[ "$(tr -d '\n' < "$work/state/relay-token")" = "$token" ] || { printf 'error: previous relay token was not restored\n' >&2; exit 1; }
jq -e '.configured==true' "$work/public/relay.json" >/dev/null
jq -e '[.tasks[] | select(.kind=="remote-relay-configure" and .state=="failed")] | length==1' "$work/api/tasks.json" >/dev/null
jq -n '{schema:1,operation:"disable",confirmation:"DISABLE REMOTE RELAY"}' > "$work/disable.json"
env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" BEDROCK_RELAY_PUBLIC_STATUS="$work/public/relay.json" BEDROCK_RELAY_TEST_LOG="$work/systemctl.log" "$tool" "$work/disable.json" | jq -e '.status=="disabled" and .credentials_removed==true' >/dev/null
[ ! -e "$work/state/relay.json" ] && [ ! -e "$work/state/relay-token" ]
grep -Fx 'stop bedrock-relay-connector.service' "$work/systemctl.log" >/dev/null
jq -e '.schema==1 and .configured==false' "$work/public/relay.json" >/dev/null
jq -e '[.tasks[] | select(.kind=="remote-relay-disable" and .state=="succeeded")] | length==1' "$work/api/tasks.json" >/dev/null
env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" BEDROCK_RELAY_PUBLIC_STATUS="$work/public/relay.json" BEDROCK_RELAY_TEST_LOG="$work/systemctl.log" "$tool" "$work/request.json" | jq -e '.status=="configured"' >/dev/null
jq -e '.schema==1 and .configured==true' "$work/public/relay.json" >/dev/null
[ "$(tr -d '\n' < "$work/state/relay-token")" = "$token" ] || { printf 'error: relay credential was not restored on re-enable\n' >&2; exit 1; }
[ "$(grep -c '"action":"remote-relay-' "$work/api/audit.jsonl")" -eq 4 ] || { printf 'error: relay terminal audit events are missing\n' >&2; exit 1; }
jq '.confirmation="wrong"' "$work/request.json" > "$work/bad.json"
if env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" BEDROCK_RELAY_PUBLIC_STATUS="$work/public/relay.json" "$tool" "$work/bad.json" >/dev/null 2>&1; then printf 'error: bad relay confirmation was accepted\n' >&2; exit 1; fi
ln -s "$work/request.json" "$work/indirect.json"
if env BEDROCK_RELAY_CONFIG_TEST_MODE=1 BEDROCK_RELAY_CONFIG_DIR="$work/state" BEDROCK_RELAY_CONFIG_SYSTEMCTL="$work/systemctl" BEDROCK_RELAY_PUBLIC_STATUS="$work/public/relay.json" "$tool" "$work/indirect.json" >/dev/null 2>&1; then printf 'error: indirect relay request was accepted\n' >&2; exit 1; fi
printf 'Guarded remote relay configuration tests passed.\n'
