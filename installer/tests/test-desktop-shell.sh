#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TAURI="$ROOT/installer/desktop/src-tauri"
LIB="$TAURI/src/lib.rs"

python3 - "$TAURI" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
config = json.loads((root / "tauri.conf.json").read_text())
capability = json.loads((root / "capabilities/default.json").read_text())

assert config["build"]["frontendDist"] == "../../ui"
assert config["app"]["withGlobalTauri"] is True
csp = config["app"]["security"]["csp"]
assert "default-src 'self'" in csp
assert "script-src 'self'" in csp
assert "*" not in csp
assert capability["windows"] == ["main"]
assert capability["permissions"] == ["core:default"]
PY

grep -Eq '^tauri = \{ version = "2", features = \[\] \}$' "$TAURI/Cargo.toml"
if grep -q 'tauri-plugin-shell' "$TAURI/Cargo.toml"; then
  printf 'error: desktop package grants shell-plugin access\n' >&2
  exit 1
fi

[ "$(grep -c '^#\[tauri::command\]$' "$LIB")" -eq 3 ]
for command in choose_and_verify_image list_targets write_verified_image; do
  grep -q "fn $command" "$LIB"
done

if grep -Eq 'std::process|Command::new|tauri_plugin_shell|plugin\(.*shell' "$LIB"; then
  printf 'error: desktop bridge contains a general process or shell escape\n' >&2
  exit 1
fi

grep -q 'No disk operation was attempted' "$LIB"
for field in 'size_bytes: u64' 'system: bool' 'name: String' 'version: String'; do
  grep -q "$field" "$LIB"
done
if grep -Eq 'capacity: String|system_disk: bool|filename: String' "$LIB"; then
  printf 'error: desktop bridge data no longer matches the interface contract\n' >&2
  exit 1
fi
printf 'Desktop shell contract is valid.\n'
