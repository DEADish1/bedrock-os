use serde::{Deserialize, Serialize};

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
fn list_targets() -> Result<Vec<InstallTarget>, String> {
    Err(BRIDGE_UNAVAILABLE.into())
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
