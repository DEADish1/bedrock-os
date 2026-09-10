#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-stage-nas-credential"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
state="$work/nas.json"; secrets="$work/secrets"; password="$work/password"
printf '%s\n' '{"schema":1,"users":[{"name":"alice","credential_generation":0,"created_unix":1}],"groups":[],"datasets":[],"shares":[],"snapshots":[]}' > "$state"
printf '%s\n' 'correct horse battery staple' > "$password"
run() { BEDROCK_NAS_CREDENTIAL_TEST_MODE=1 BEDROCK_NAS_CREDENTIAL_STATE="$state" BEDROCK_NAS_CREDENTIAL_BASE="$secrets" "$tool" "$@"; }
run alice "$password" 'STAGE NAS CREDENTIAL — alice' > "$work/result.json"
jq -e '.status=="staged" and .user=="alice" and .secret_recorded==false' "$work/result.json" >/dev/null
jq -e '.users[0].credential_candidate==true' "$state" >/dev/null
[ "$(stat -c %a "$secrets")" = 700 ] && [ "$(stat -c %a "$secrets/alice.password")" = 600 ]
cmp -s "$password" "$secrets/alice.password"
! grep -q 'correct horse' "$state" "$work/result.json"
if run alice "$password" 'STAGE NAS CREDENTIAL — alice' >/dev/null 2>&1; then printf 'error: existing staged credential was overwritten\n' >&2; exit 1; fi
if run alice "$password" wrong >/dev/null 2>&1; then printf 'error: wrong staging confirmation accepted\n' >&2; exit 1; fi
if run missing "$password" 'STAGE NAS CREDENTIAL — missing' >/dev/null 2>&1; then printf 'error: unmanaged user accepted\n' >&2; exit 1; fi
rm -f "$secrets/alice.password"
ln -s "$password" "$work/indirect"; if [ -L "$work/indirect" ] && run alice "$work/indirect" 'STAGE NAS CREDENTIAL — alice' >/dev/null 2>&1; then printf 'error: indirect password file accepted\n' >&2; exit 1; fi
printf 'NAS credential staging tests passed.\n'
