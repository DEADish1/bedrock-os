use serde::{Deserialize, Serialize};
use std::path::Path;
use std::process::Command;
use tauri::{path::BaseDirectory, Manager};

const BRIDGE_UNAVAILABLE: &str =
    "The protected disk service is not connected. No disk operation was attempted.";

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct InstallTarget {
    id: String,
    path: String,
    model: String,
    size_bytes: u64,
    removable: bool,
    system: bool,
    mounted: bool,
    read_only: bool,
}

#[derive(Debug, Deserialize)]
struct TargetInventory {
    schema: u8,
    targets: Vec<InstallTarget>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct VerifiedImage {
    name: String,
    version: String,
    size_bytes: u64,
    sha256: String,
    image_type: String,
}

#[tauri::command]
fn choose_and_verify_image() -> Result<VerifiedImage, String> {
    Err(BRIDGE_UNAVAILABLE.into())
}

#[tauri::command]
fn list_targets(handle: tauri::AppHandle) -> Result<Vec<InstallTarget>, String> {
    let relative_path = platform_adapter_path();
    let script = handle
        .path()
        .resolve(relative_path, BaseDirectory::Resource)
        .map_err(|_| "The removable-drive scanner could not be located.".to_string())?;
    let output = run_inventory_adapter(&script)?;
    parse_inventory(&output)
}

#[cfg(target_os = "windows")]
fn platform_adapter_path() -> &'static str {
    "adapters/windows-list-targets.ps1"
}

#[cfg(target_os = "macos")]
fn platform_adapter_path() -> &'static str {
    "adapters/macos-list-targets.sh"
}

#[cfg(all(unix, not(target_os = "macos")))]
fn platform_adapter_path() -> &'static str {
    "adapters/linux-list-targets.sh"
}

fn run_inventory_adapter(script: &Path) -> Result<Vec<u8>, String> {
    #[cfg(target_os = "windows")]
    let mut command = {
        let mut command = Command::new("powershell.exe");
        command.args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ]);
        command.arg(script);
        command
    };

    #[cfg(not(target_os = "windows"))]
    let mut command = {
        let mut command = Command::new("/bin/sh");
        command.arg(script);
        command
    };

    let output = command
        .output()
        .map_err(|_| "The removable-drive scanner could not start.".to_string())?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr);
        let detail = detail.lines().last().unwrap_or("unknown scanner error");
        return Err(format!("Drive scan failed: {detail}"));
    }
    Ok(output.stdout)
}

fn parse_inventory(bytes: &[u8]) -> Result<Vec<InstallTarget>, String> {
    let inventory: TargetInventory = serde_json::from_slice(bytes)
        .map_err(|_| "The removable-drive scanner returned invalid data.".to_string())?;
    if inventory.schema != 1 {
        return Err("The removable-drive scanner returned an unsupported format.".into());
    }
    if inventory.targets.iter().any(|target| {
        target.id.is_empty()
            || target.path.is_empty()
            || target.model.is_empty()
            || target.size_bytes == 0
    }) {
        return Err("The removable-drive scanner returned an incomplete drive record.".into());
    }
    Ok(inventory.targets)
}

#[tauri::command]
fn write_verified_image(
    _image: VerifiedImage,
    _target_id: String,
    _confirmation: String,
) -> Result<(), String> {
    Err(BRIDGE_UNAVAILABLE.into())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            choose_and_verify_image,
            list_targets,
            write_verified_image
        ])
        .run(tauri::generate_context!())
        .expect("Bedrock Installer could not start");
}

#[cfg(test)]
mod tests {
    use super::parse_inventory;

    #[test]
    fn accepts_shared_inventory_contract() {
        let targets = parse_inventory(br#"{"schema":1,"targets":[{"id":"linux:test","path":"/dev/test","model":"Test USB","sizeBytes":8589934592,"removable":true,"system":false,"mounted":false,"readOnly":false}]}"#).unwrap();
        assert_eq!(targets.len(), 1);
        assert_eq!(targets[0].model, "Test USB");
    }

    #[test]
    fn rejects_incomplete_inventory() {
        let error = parse_inventory(br#"{"schema":1,"targets":[{"id":"","path":"/dev/test","model":"Test USB","sizeBytes":8589934592,"removable":true,"system":false,"mounted":false,"readOnly":false}]}"#).unwrap_err();
        assert!(error.contains("incomplete"));
    }
}
