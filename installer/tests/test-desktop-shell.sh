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
assert config["bundle"]["icon"] == ["icons/icon.png", "icons/icon.ico"]
assert (root / "icons/icon.png").stat().st_size > 0
assert (root / "icons/icon.ico").stat().st_size > 0
assert config["bundle"]["resources"] == {
    "../../adapters/linux-list-targets.sh": "adapters/linux-list-targets.sh",
    "../../adapters/macos-list-targets.sh": "adapters/macos-list-targets.sh",
    "../../adapters/windows-list-targets.ps1": "adapters/windows-list-targets.ps1",
}
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

if grep -Eq 'tauri_plugin_shell|plugin\(.*shell' "$LIB"; then
  printf 'error: desktop bridge contains a general shell escape\n' >&2
  exit 1
fi

grep -q 'Command::new("/bin/sh")' "$LIB"
grep -q 'Command::new("powershell.exe")' "$LIB"
grep -q 'fn parse_inventory' "$LIB"
grep -q '"size_bytes":8589934592' "$LIB"
grep -q '"read_only":false' "$LIB"
grep -q 'blocking_pick_file' "$LIB"
grep -q 'fn verify_signed_release' "$LIB"
grep -q 'fn verify_cms_signature' "$LIB"
grep -q 'This development build has no release trust certificate' "$LIB"
grep -q 'tauri-plugin-dialog = "2"' "$TAURI/Cargo.toml"
grep -q 'openssl = { version = "0.10", features = \["vendored"\] }' "$TAURI/Cargo.toml"
grep -q 'uuid = { version = "1", features = \["v4"\] }' "$TAURI/Cargo.toml"
grep -q 'zstd = "0.13"' "$TAURI/Cargo.toml"
grep -q 'production installer builds require BEDROCK_INSTALLER_TRUST_CERT' "$TAURI/build.rs"
grep -q 'session_id: String' "$LIB"
grep -q 'struct InstallerState' "$LIB"
grep -q 'manage(InstallerState::default())' "$LIB"
grep -q 'verify_signed_release(&session.image_path' "$LIB"
grep -q 'let targets = scan_targets(&handle)' "$LIB"
grep -q 'fn validate_write_target' "$LIB"
grep -q 'mod media_writer;' "$LIB"
grep -q 'fn write_verified_media' "$TAURI/src/media_writer.rs"
grep -q 'The written media checksum does not match the signed release' "$TAURI/src/media_writer.rs"
grep -q 'fn protected_writer_preflight' "$LIB"
grep -q 'deny_unknown_fields' "$LIB"
grep -q 'MAX_HELPER_REQUEST_BYTES' "$LIB"
grep -q 'HELPER_REQUEST_LIFETIME_SECONDS' "$LIB"
grep -q 'run_protected_writer_helper' "$TAURI/src/bin/bedrock-media-writer.rs"
node --check "$ROOT/installer/desktop/scripts/prepare-release-sidecar.mjs"
if env -u BEDROCK_REQUIRE_PRODUCTION_TRUST -u BEDROCK_INSTALLER_TRUST_CERT \
  node "$ROOT/installer/desktop/scripts/prepare-release-sidecar.mjs" >/dev/null 2>&1; then
  printf 'error: release sidecar staging accepted missing production trust\n' >&2
  exit 1
fi

python3 - "$TAURI" <<'PY'
import json
import pathlib
import plistlib
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
release = json.loads((root / "tauri.release.conf.json").read_text())
bundle = release["bundle"]
assert bundle["externalBin"] == ["binaries/bedrock-media-writer"]
policy = root / "elevation/linux/com.bedrock.server.installer.write.policy"
windows = root / "elevation/windows/bedrock-media-writer.exe.manifest"
macos = root / "elevation/macos/com.bedrock.server.installer.writer.plist"
ET.parse(policy)
ET.parse(windows)
with macos.open("rb") as stream:
    plist = plistlib.load(stream)
assert plist["Label"] == "com.bedrock.server.installer.writer"
assert plist["BundleProgram"] == "Contents/MacOS/bedrock-media-writer"
assert bundle["macOS"]["minimumSystemVersion"] == "13.0"
assert "/usr/share/polkit-1/actions/com.bedrock.server.installer.write.policy" in bundle["linux"]["deb"]["files"]
PY

grep -q 'rustc-link-arg-bin=bedrock-media-writer=/MANIFEST:EMBED' "$TAURI/build.rs"
grep -q 'requestedExecutionLevel level="requireAdministrator"' "$TAURI/elevation/windows/bedrock-media-writer.exe.manifest"
grep -q '<allow_active>auth_admin</allow_active>' "$TAURI/elevation/linux/com.bedrock.server.installer.write.policy"
grep -q 'org.freedesktop.policykit.exec.path' "$TAURI/elevation/linux/com.bedrock.server.installer.write.policy"

if grep -q 'dialog:' "$TAURI/capabilities/default.json"; then
  printf 'error: the frontend must not receive direct dialog-plugin permission\n' >&2
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
