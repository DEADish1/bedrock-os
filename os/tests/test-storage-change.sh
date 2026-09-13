#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wrapper="$ROOT/os/config/includes.chroot/usr/lib/bedrock/change-storage"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/requests"
jq -n '{schema:1,pools:[{name:"vault",backend:"zfs",layout:"mirror",devices:["/dev/sdb","/dev/sdc"],state:"online",last_scrub_unix:null,last_operation_unix:1},{name:"archive",backend:"mdraid",layout:"raid6",devices:["/dev/sdd"],state:"exported",last_scrub_unix:null,last_operation_unix:1}]}' > "$work/state.json"
jq -n '{schema:1,generated_unix:10,disks:[
  {id:"disk-00000000000000000001",path:"/dev/sdb",model:"Old 1",size_bytes:1000000000000,transport:"sata",health:"healthy",eligible:false,reason:"managed"},
  {id:"disk-00000000000000000002",path:"/dev/sdc",model:"Old 2",size_bytes:1000000000000,transport:"sata",health:"healthy",eligible:false,reason:"managed"},
  {id:"disk-00000000000000000003",path:"/dev/sde",model:"New 1",size_bytes:1000000000000,transport:"sata",health:"healthy",eligible:true,reason:"available"},
  {id:"disk-00000000000000000004",path:"/dev/sdf",model:"New 2",size_bytes:1000000000000,transport:"sata",health:"healthy",eligible:true,reason:"available"}]}' > "$work/candidates.json"
cat > "$work/manager" <<'EOF'
#!/bin/sh
cat "$1" >> "$BEDROCK_STORAGE_ACTION_CALLS"
EOF
chmod +x "$work/manager"
run() { BEDROCK_STORAGE_ACTION_TEST_MODE=1 BEDROCK_STORAGE_ACTION_MANAGER="$work/manager" BEDROCK_STORAGE_ACTION_STATE="$work/state.json" BEDROCK_STORAGE_ACTION_CANDIDATES="$work/candidates.json" BEDROCK_STORAGE_ACTION_OUTPUT="$work/requests/operation.json" BEDROCK_STORAGE_ACTION_CALLS="$work/calls" "$wrapper" "$work/request.json"; }
jq -n '{schema:1,id:"vault",operation:"scrub",confirmation:"SCRUB STORAGE vault"}' > "$work/request.json"
run
jq -e '.schema==1 and .action=="scrub" and .backend=="zfs" and .pool=="vault" and .devices==[] and .confirmation=="SCRUB — vault"' "$work/calls" >/dev/null
[ ! -e "$work/requests/operation.json" ]
jq -n '{schema:1,id:"vault",operation:"export",confirmation:"EXPORT STORAGE vault"}' > "$work/request.json"; run
jq -n '{schema:1,id:"archive",operation:"import",confirmation:"IMPORT STORAGE archive"}' > "$work/request.json"; run
jq -s -e '.[1].action=="export" and .[1].confirmation=="EXPORT — vault" and .[2].action=="import" and .[2].backend=="mdraid" and .[2].confirmation=="IMPORT — archive"' "$work/calls" >/dev/null
jq -n '{schema:1,id:"newpool",operation:"create",backend:"zfs",layout:"mirror",disk_ids:["disk-00000000000000000003","disk-00000000000000000004"],confirmation:"CREATE STORAGE newpool USING disk-00000000000000000003,disk-00000000000000000004"}' > "$work/request.json"; run
jq -n '{schema:1,id:"vault",operation:"expand",disk_ids:["disk-00000000000000000003","disk-00000000000000000004"],confirmation:"EXPAND STORAGE vault USING disk-00000000000000000003,disk-00000000000000000004"}' > "$work/request.json"; run
jq -n '{schema:1,id:"vault",operation:"replace",old_disk_id:"disk-00000000000000000001",new_disk_id:"disk-00000000000000000003",confirmation:"REPLACE STORAGE vault MEMBER disk-00000000000000000001 WITH disk-00000000000000000003"}' > "$work/request.json"; run
jq -s -e '.[3].action=="create" and .[3].devices==["/dev/sde","/dev/sdf"] and .[3].confirmation=="ERASE AND CREATE — newpool — zfs mirror — /dev/sde, /dev/sdf" and
  .[4].action=="expand" and .[4].backend=="zfs" and .[4].devices==["/dev/sde","/dev/sdf"] and
  .[5].action=="replace" and .[5].devices==["/dev/sdb","/dev/sde"]' "$work/calls" >/dev/null
jq '.new_disk_id="disk-00000000000000000002" | .confirmation="REPLACE STORAGE vault MEMBER disk-00000000000000000001 WITH disk-00000000000000000002"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: managed replacement disk accepted as new media\n' >&2; exit 1; fi
jq -n '{schema:1,id:"vault",operation:"scrub",confirmation:"SCRUB STORAGE vault"}' > "$work/request.json"
jq '.confirmation="wrong"' "$work/request.json" > "$work/bad.json"; mv "$work/bad.json" "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: invalid storage action accepted\n' >&2; exit 1; fi
jq -n '{schema:1,id:"missing",operation:"scrub",confirmation:"SCRUB STORAGE missing"}' > "$work/request.json"
if run >/dev/null 2>&1; then printf 'error: unknown storage accepted\n' >&2; exit 1; fi
printf 'Storage action wrapper tests passed.\n'
