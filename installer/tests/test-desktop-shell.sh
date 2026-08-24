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
grep -q '^cc = "1"$' "$TAURI/Cargo.toml"
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
grep -q 'base64 = "0.22"' "$TAURI/Cargo.toml"
grep -q 'windows-sys = { version = "0.61"' "$TAURI/Cargo.toml"
grep -q '"Win32_Security"' "$TAURI/Cargo.toml"
grep -q 'libc = "0.2"' "$TAURI/Cargo.toml"
grep -q 'production installer builds require BEDROCK_INSTALLER_TRUST_CERT' "$TAURI/build.rs"
grep -q 'production macOS installer builds require BEDROCK_APPLE_TEAM_ID' "$TAURI/build.rs"
grep -q 'src/macos_service.m' "$TAURI/build.rs"
grep -q 'session_id: String' "$LIB"
grep -q 'struct InstallerState' "$LIB"
grep -q 'manage(InstallerState::default())' "$LIB"
grep -q 'verify_signed_release(&session.image_path' "$LIB"
grep -q 'let targets = scan_targets(&handle)' "$LIB"
grep -q 'fn validate_write_target' "$LIB"
grep -q 'mod media_writer;' "$LIB"
grep -q 'mod device_finalizer;' "$LIB"
grep -q 'mod write_pipeline;' "$LIB"
grep -q 'mod physical_device;' "$LIB"
grep -q 'fn write_verified_media' "$TAURI/src/media_writer.rs"
grep -q 'fn finalize_written_device' "$TAURI/src/device_finalizer.rs"
grep -q 'fn write_verify_and_finalize' "$TAURI/src/write_pipeline.rs"
grep -q 'struct LinuxPhysicalDevice' "$TAURI/src/physical_device.rs"
grep -q 'BEDROCK_ENABLE_PHYSICAL_WRITER' "$TAURI/build.rs"
grep -q 'I_ACCEPT_REAL_DEVICE_DATA_LOSS' "$TAURI/build.rs"
grep -q 'physical writer builds require BEDROCK_REQUIRE_PRODUCTION_TRUST' "$TAURI/build.rs"
grep -q 'target_os != "linux"' "$TAURI/build.rs"
grep -q 'normal_build_keeps_physical_writing_disabled' "$LIB"
grep -q 'ProtectedWriterResult::WriteComplete' "$LIB"
grep -q 'verification_failure_never_reaches_finalization' "$TAURI/src/write_pipeline.rs"
grep -q 'synchronization_failure_never_attempts_eject' "$TAURI/src/write_pipeline.rs"
grep -q 'fn synchronize_cache' "$TAURI/src/device_finalizer.rs"
grep -q 'fn try_eject' "$TAURI/src/device_finalizer.rs"
grep -q 'BLKFLSBUF' "$TAURI/src/device_finalizer.rs"
grep -q 'FlushFileBuffers' "$TAURI/src/device_finalizer.rs"
grep -q 'IOCTL_STORAGE_EJECT_MEDIA' "$TAURI/src/device_finalizer.rs"
grep -q 'IOCTL_STORAGE_MEDIA_REMOVAL' "$TAURI/src/device_finalizer.rs"
grep -q 'bedrock_macos_synchronize_disk' "$TAURI/src/device_finalizer.rs"
grep -q 'DKIOCSYNCHRONIZECACHE' "$TAURI/src/macos_service.m"
grep -q 'DKIOCEJECT' "$TAURI/src/macos_service.m"
grep -q 'The written media checksum does not match the signed release' "$TAURI/src/media_writer.rs"
grep -q 'fn protected_writer_preflight' "$LIB"
grep -q 'deny_unknown_fields' "$LIB"
grep -q 'MAX_HELPER_REQUEST_BYTES' "$LIB"
grep -q 'HELPER_REQUEST_LIFETIME_SECONDS' "$LIB"
grep -q 'run_protected_writer_helper' "$TAURI/src/bin/bedrock-media-writer.rs"
grep -q 'Command::new("/usr/bin/pkexec")' "$LIB"
grep -q '\.arg("/usr/bin/bedrock-media-writer")' "$LIB"
grep -q 'OsStr::new("runas")' "$LIB"
grep -q 'ShellExecuteExW' "$LIB"
grep -q 'HELPER_PREFLIGHT_ONLY_EXIT' "$LIB"
grep -q 'fn validate_elevated_identity' "$LIB"
grep -q 'libc::geteuid() == 0' "$LIB"
grep -q 'TokenIsElevated != 0' "$LIB"
grep -q 'bedrock_macos_send_writer_request' "$LIB"
grep -q 'bedrock_macos_run_writer_service' "$LIB"
grep -q 'fn open_exclusive_whole_device' "$LIB"
grep -q 'libc::O_EXCL' "$LIB"
grep -q 'sysfs.*join("partition")\|join("partition")' "$LIB"
grep -q 'IOCTL_DISK_GET_LENGTH_INFO' "$LIB"
grep -q 'GENERIC_READ | GENERIC_WRITE' "$LIB"
grep -q 'bedrock_macos_probe_exclusive_disk' "$LIB"
grep -q 'O_EXLOCK' "$TAURI/src/macos_service.m"
grep -q 'DKIOCGETBLOCKCOUNT' "$TAURI/src/macos_service.m"
grep -q 'certificate leaf\[subject.OU\]' "$LIB"
grep -q 'setConnectionCodeSigningRequirement' "$TAURI/src/macos_service.m"
grep -q 'setCodeSigningRequirement' "$TAURI/src/macos_service.m"
grep -q 'daemonServiceWithPlistName' "$TAURI/src/macos_service.m"
grep -q 'NSXPCConnectionPrivileged' "$TAURI/src/macos_service.m"
grep -q 'BEDROCK_APPLE_SIGNING_IDENTITY' "$ROOT/installer/desktop/scripts/prepare-release-sidecar.mjs"
grep -q '"--verify", "--strict", "--verbose=2"' "$ROOT/installer/desktop/scripts/prepare-release-sidecar.mjs"
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
assert plist["AssociatedBundleIdentifiers"] == ["os.bedrock.installer"]
assert bundle["macOS"]["minimumSystemVersion"] == "13.0"
assert "/usr/share/polkit-1/actions/com.bedrock.server.installer.write.policy" in bundle["linux"]["deb"]["files"]
PY

! grep -q 'rustc-link-arg-bin=bedrock-media-writer' "$TAURI/build.rs"
grep -q 'process.env.MT || "mt.exe"' "$ROOT/installer/desktop/scripts/prepare-release-sidecar.mjs"
grep -q '\-outputresource:${source};#1' "$ROOT/installer/desktop/scripts/prepare-release-sidecar.mjs"
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
