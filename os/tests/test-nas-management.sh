#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool="$ROOT/os/config/includes.chroot/usr/sbin/bedrock-nas"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
state=$work/state.json audit=$work/audit.jsonl
req() {
  jq -n --arg action "$1" --arg name "$2" --arg pool "$3" --arg subject "$4" --argjson quota "$5" \
    --argjson protocols "$6" --argjson ro "$7" --argjson recycle "$8" --argjson tm "$9" --arg confirmation "${10}" \
    '{schema:1,action:$action,name:$name,pool:$pool,subject:$subject,quota_bytes:$quota,protocols:$protocols,read_only:$ro,recycle:$recycle,time_machine:$tm,confirmation:$confirmation}'
}
run() { BEDROCK_NAS_TEST_MODE=1 BEDROCK_NAS_TEST_ROOT="$work/root" BEDROCK_NAS_TEST_NOW="$1" BEDROCK_NAS_TEST_AUDIT="$audit" "$tool" "$2" "$3" "$state"; }

req create-user alice '' '' 0 '[]' false false false 'CREATE USER — alice' > "$work/user.json"; run 10 apply "$work/user.json" >/dev/null
req create-group family '' '' 0 '[]' false false false 'CREATE GROUP — family' > "$work/group.json"; run 11 apply "$work/group.json" >/dev/null
req add-member family '' alice 0 '[]' false false false 'ADD MEMBER — alice — family' > "$work/member.json"; run 12 apply "$work/member.json" >/dev/null
printf '%s\n' 'correct horse battery staple' > "$work/password"
req rotate-credential alice '' '' 0 '[]' false false false 'ROTATE CREDENTIAL — alice' > "$work/rotate.json"
BEDROCK_NAS_PASSWORD_FILE="$work/password" run 13 apply "$work/rotate.json" >/dev/null
unset BEDROCK_NAS_PASSWORD_FILE
req create-dataset family vault '' 0 '[]' false false false 'CREATE DATASET — vault/family' > "$work/dataset.json"; run 14 apply "$work/dataset.json" >/dev/null
req set-quota family vault '' 1000000000000 '[]' false false false 'SET QUOTA — vault/family — 1000000000000' > "$work/quota.json"; run 15 apply "$work/quota.json" >/dev/null
req set-acl family vault family 0 '[]' false false false 'SET ACL — vault/family — family' > "$work/acl.json"; run 16 apply "$work/acl.json" >/dev/null
req create-share family vault family 0 '["smb","nfs"]' false true false 'CREATE SHARE — vault/family — smb,nfs — family' > "$work/share.json"; run 17 apply "$work/share.json" >/dev/null
req snapshot family vault '' 0 '[]' false false false 'SNAPSHOT — vault/family' > "$work/snapshot.json"; run 18 apply "$work/snapshot.json" >/dev/null
jq -e '
  .users[0].credential_generation == 1 and .groups[0].members == ["alice"] and
  .datasets[0].quota_bytes == 1000000000000 and .datasets[0].acl_subjects == ["family"] and
  .shares[0].protocols == ["smb","nfs"] and .shares[0].recycle == true and (.snapshots|length)==1
' "$state" >/dev/null
! grep -q 'correct horse' "$state" "$audit"
req destroy-snapshot family vault '' 0 '[]' false false false 'DESTROY SNAPSHOT — vault/family' > "$work/destroy.json"; run 19 apply "$work/destroy.json" >/dev/null
jq -e '(.snapshots|length)==0' "$state" >/dev/null

req create-dataset timemachine vault '' 0 '[]' false false false 'CREATE DATASET — vault/timemachine' > "$work/tm-dataset.json"; run 20 apply "$work/tm-dataset.json" >/dev/null
req set-quota timemachine vault '' 2000000000000 '[]' false false false 'SET QUOTA — vault/timemachine — 2000000000000' > "$work/tm-quota.json"; run 21 apply "$work/tm-quota.json" >/dev/null
req create-share timemachine vault family 0 '["smb"]' false false true 'CREATE SHARE — vault/timemachine — smb — family' > "$work/tm-share.json"; run 22 apply "$work/tm-share.json" >/dev/null

req create-share backup vault family 0 '["smb"]' false false true 'CREATE SHARE — vault/backup — smb — family' > "$work/tm-missing-dataset.json"
if run 23 apply "$work/tm-missing-dataset.json" >/dev/null 2>&1; then printf 'error: share accepted a missing dataset\n' >&2; exit 1; fi
req rotate-credential alice '' '' 0 '[]' false false false 'ROTATE CREDENTIAL — alice' > "$work/no-secret.json"
if run 24 apply "$work/no-secret.json" >/dev/null 2>&1; then printf 'error: credential rotation accepted no secret file\n' >&2; exit 1; fi
ln -s "$work/user.json" "$work/indirect.json"
if run 25 plan "$work/indirect.json" >/dev/null 2>&1; then printf 'error: NAS tool accepted an indirect request\n' >&2; exit 1; fi
[ "$(wc -l < "$audit" | tr -d ' ')" -eq 13 ]
BEDROCK_NAS_RENDER_TEST_MODE=1 "$ROOT/os/config/includes.chroot/usr/lib/bedrock/render-nas-services" "$state" "$work/services" >/dev/null
grep -q '^\[family\]$' "$work/services/smb.conf"
grep -q '^   vfs objects = recycle catia fruit streams_xattr$' "$work/services/smb.conf"
grep -q '^   fruit:time machine = yes$' "$work/services/smb.conf"
jq -e 'length==1 and .[0].path=="/srv/bedrock/pools/vault/family" and .[0].options=="rw,sync,no_subtree_check,root_squash"' "$work/services/nfs-exports.json" >/dev/null
grep -q '^ExecStart=/usr/sbin/smbd .*--configfile=/var/lib/bedrock/storage/services/smb.conf$' "$ROOT/os/config/includes.chroot/etc/systemd/system/smbd.service.d/bedrock.conf"
printf 'Bedrock NAS datasets, shares, permissions, snapshots, and credential tests passed.\n'
