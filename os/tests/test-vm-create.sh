#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
creator="$ROOT/os/config/includes.chroot/usr/lib/bedrock/create-vm"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin" "$work/state"; : > "$work/tasks.log"
cat > "$work/bin/planner" <<'EOF'
#!/bin/sh
jq -S '{schema:1,status:"review-only",mutation_authorized:false,name,vcpus,memory_mib,disk_size_gib,firmware,network,autostart,confirmation_phrase:("CREATE VM "+.name),reservation:{host_cpus:16,used_vcpus:0,bedrock_reserved_cpus:2,host_memory_mib:32768,used_memory_mib:0,bedrock_reserved_memory_mib:2048}}' "$1" > "$2"
EOF
cat > "$work/bin/renderer" <<'EOF'
#!/bin/sh
printf '<domain><name>%s</name></domain>\n' "$(jq -r .name "$1")" > "$2"
EOF
cat > "$work/bin/registrar" <<'EOF'
#!/bin/sh
jq -e --arg plan "$(sha256sum "$1"|awk '{print $1}')" --arg definition "$(sha256sum "$2"|awk '{print $1}')" '.plan_sha256==$plan and .definition_sha256==$definition and .confirmation=="CREATE VM test-vm"' "$3" >/dev/null
printf '%s\n' "$*" > "$BEDROCK_VM_CREATE_CALLS"
EOF
cat > "$work/bin/task" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BEDROCK_VM_TASK_LOG"
EOF
chmod +x "$work/bin/"*
jq -n '{schema:1,name:"test-vm",vcpus:4,memory_mib:8192,disk_size_gib:64,autostart:false,confirmation:"CREATE VM test-vm"}' > "$work/request.json"
BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/state" BEDROCK_VM_CREATE_PLANNER="$work/bin/planner" BEDROCK_VM_CREATE_RENDERER="$work/bin/renderer" BEDROCK_VM_CREATE_REGISTRAR="$work/bin/registrar" BEDROCK_RECORD_API_TASK="$work/bin/task" BEDROCK_VM_TASK_LOG="$work/tasks.log" BEDROCK_VM_CREATE_CALLS="$work/calls" "$creator" "$work/request.json" | jq -e '.status=="registered" and .name=="test-vm"' >/dev/null
[ -f "$work/state/definitions/test-vm.xml" ] && [ ! -e "$work/state/plans/test-vm.json" ] && [ ! -e "$work/state/authorizations/test-vm.json" ]
grep -Eq '^vm-create-[0-9]+ vm-create succeeded [0-9]+ 4 4 steps$' "$work/tasks.log"
jq '.confirmation="CREATE VM other"' "$work/request.json" > "$work/bad.json"
if BEDROCK_VM_TEST_MODE=1 BEDROCK_VM_STATE_ROOT="$work/other" BEDROCK_VM_CREATE_PLANNER="$work/bin/planner" BEDROCK_VM_CREATE_RENDERER="$work/bin/renderer" BEDROCK_VM_CREATE_REGISTRAR="$work/bin/registrar" BEDROCK_RECORD_API_TASK="$work/bin/task" BEDROCK_VM_TASK_LOG="$work/tasks.log" "$creator" "$work/bad.json" >/dev/null 2>&1; then echo 'invalid confirmation accepted' >&2; exit 1; fi
printf 'VM creation orchestration tests passed.\n'
