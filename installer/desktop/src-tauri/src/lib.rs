use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use tauri::{path::BaseDirectory, Manager, State};
use tauri_plugin_dialog::DialogExt;
use uuid::Uuid;

mod media_writer;

const RELEASE_TRUST_CERT_PEM: &[u8] =
    include_bytes!(concat!(env!("OUT_DIR"), "/bedrock-release-trust.pem"));

const BRIDGE_UNAVAILABLE: &str =
    "The protected disk service is not connected. No disk operation was attempted.";
const MINIMUM_TARGET_SIZE: u64 = 8 * 1024 * 1024 * 1024;

#[derive(Clone, Debug, Deserialize, Serialize)]
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

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
struct VerifiedImage {
    session_id: String,
    name: String,
    version: String,
    size_bytes: u64,
    sha256: String,
    image_type: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ReleaseManifest {
    schema: u8,
    product: String,
    architecture: String,
    version: String,
    artifact: ReleaseArtifact,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ReleaseArtifact {
    name: String,
    #[serde(rename = "type")]
    image_type: String,
    sha256: String,
    size: u64,
    write_sha256: String,
    write_size: u64,
}

#[derive(Clone)]
struct VerifiedSession {
    image_path: PathBuf,
    public: VerifiedImage,
}

#[derive(Default)]
struct InstallerState {
    verified: Mutex<Option<VerifiedSession>>,
}

#[tauri::command]
fn choose_and_verify_image(
    handle: tauri::AppHandle,
    state: State<'_, InstallerState>,
) -> Result<VerifiedImage, String> {
    *state
        .verified
        .lock()
        .map_err(|_| "The verified-image session could not be reset.".to_string())? = None;
    let selection = handle
        .dialog()
        .file()
        .add_filter("Bedrock OS images", &["iso", "zst"])
        .blocking_pick_file()
        .ok_or_else(|| "No image was selected.".to_string())?;
    let image_path = selection
        .into_path()
        .map_err(|_| "The selected image is not a local file.".to_string())?;
    let manifest = verify_signed_release(&image_path, RELEASE_TRUST_CERT_PEM)?;
    let verified = VerifiedImage {
        session_id: Uuid::new_v4().to_string(),
        name: manifest.artifact.name,
        version: manifest.version,
        size_bytes: manifest.artifact.size,
        sha256: manifest.artifact.sha256,
        image_type: manifest.artifact.image_type,
    };
    let mut session = state
        .verified
        .lock()
        .map_err(|_| "The verified-image session could not be stored.".to_string())?;
    *session = Some(VerifiedSession {
        image_path,
        public: verified.clone(),
    });
    Ok(verified)
}

fn verify_signed_release(image_path: &Path, trust_cert_pem: &[u8]) -> Result<ReleaseManifest, String> {
    let release_dir = image_path
        .parent()
        .ok_or_else(|| "The selected image has no release folder.".to_string())?;
    let manifest_path = release_dir.join("manifest.json");
    let signature_path = release_dir.join("manifest.p7s");
    let manifest_bytes = std::fs::read(&manifest_path)
        .map_err(|_| "The signed release manifest is missing.".to_string())?;
    let signature = std::fs::read(&signature_path)
        .map_err(|_| "The release signature is missing.".to_string())?;
    if signature.is_empty() {
        return Err("The release signature is empty.".into());
    }
    let manifest: ReleaseManifest = serde_json::from_slice(&manifest_bytes)
        .map_err(|_| "The release manifest format is invalid.".to_string())?;
    validate_manifest(&manifest, image_path)?;
    let (size, sha256) = hash_file(image_path)?;
    if size != manifest.artifact.size {
        return Err("The selected image size does not match its signed manifest.".into());
    }
    if sha256 != manifest.artifact.sha256 {
        return Err("The selected image checksum does not match its signed manifest.".into());
    }
    verify_cms_signature(&manifest_bytes, &signature, trust_cert_pem)?;
    Ok(manifest)
}

fn verify_cms_signature(
    manifest: &[u8],
    signature_der: &[u8],
    trust_cert_pem: &[u8],
) -> Result<(), String> {
    if trust_cert_pem.is_empty() {
        return Err("This development build has no release trust certificate. No image was accepted.".into());
    }
    let certificate = X509::from_pem(trust_cert_pem)
        .map_err(|_| "The embedded release trust certificate is invalid.".to_string())?;
    let mut store = X509StoreBuilder::new()
        .map_err(|_| "The release trust store could not be created.".to_string())?;
    store
        .add_cert(certificate)
        .map_err(|_| "The release trust certificate could not be loaded.".to_string())?;
    let store = store.build();
    let mut cms = CmsContentInfo::from_der(signature_der)
        .map_err(|_| "The release signature format is invalid.".to_string())?;
    cms.verify(
        None,
        Some(&store),
        Some(manifest),
        None,
        CMSOptions::BINARY,
    )
    .map_err(|_| "The release manifest signature is not trusted or has been changed.".to_string())
}

fn validate_manifest(manifest: &ReleaseManifest, image_path: &Path) -> Result<(), String> {
    let filename = image_path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| "The selected image filename is invalid.".to_string())?;
    let valid_name = filename == "bedrock-os-amd64.iso" || filename == "bedrock-os-amd64.raw.zst";
    let valid_type = (manifest.artifact.image_type == "iso" && filename.ends_with(".iso"))
        || (manifest.artifact.image_type == "raw-zst" && filename.ends_with(".raw.zst"));
    if manifest.schema != 1
        || manifest.product != "Bedrock Server OS"
        || manifest.architecture != "amd64"
        || manifest.version.is_empty()
        || manifest.artifact.name != filename
        || !valid_name
        || !valid_type
        || manifest.artifact.size == 0
        || manifest.artifact.write_size == 0
        || !is_sha256(&manifest.artifact.sha256)
        || !is_sha256(&manifest.artifact.write_sha256)
    {
        return Err("The release manifest contains unsupported or unsafe values.".into());
    }
    if manifest.artifact.image_type == "iso"
        && (manifest.artifact.write_size != manifest.artifact.size
            || manifest.artifact.write_sha256 != manifest.artifact.sha256)
    {
        return Err("The ISO write identity does not match the selected image.".into());
    }
    Ok(())
}

fn is_sha256(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

fn hash_file(path: &Path) -> Result<(u64, String), String> {
    let mut file = File::open(path).map_err(|_| "The selected image could not be opened.".to_string())?;
    let mut digest = Sha256::new();
    let mut size = 0_u64;
    let mut buffer = [0_u8; 1024 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|_| "The selected image could not be read completely.".to_string())?;
        if read == 0 {
            break;
        }
        size += read as u64;
        digest.update(&buffer[..read]);
    }
    Ok((size, format!("{:x}", digest.finalize())))
}

#[tauri::command]
fn list_targets(handle: tauri::AppHandle) -> Result<Vec<InstallTarget>, String> {
    scan_targets(&handle)
}

fn scan_targets(handle: &tauri::AppHandle) -> Result<Vec<InstallTarget>, String> {
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
    handle: tauri::AppHandle,
    state: State<'_, InstallerState>,
    image: VerifiedImage,
    target_id: String,
    confirmation: String,
) -> Result<(), String> {
    let session = state
        .verified
        .lock()
        .map_err(|_| "The verified-image session could not be read.".to_string())?
        .clone()
        .ok_or_else(|| "Choose and verify the Bedrock image again before writing.".to_string())?;
    if session.public != image {
        return Err("The verified-image session does not match. Choose the image again.".into());
    }

    let manifest = verify_signed_release(&session.image_path, RELEASE_TRUST_CERT_PEM)?;
    if manifest.artifact.name != image.name
        || manifest.version != image.version
        || manifest.artifact.size != image.size_bytes
        || manifest.artifact.sha256 != image.sha256
        || manifest.artifact.image_type != image.image_type
    {
        return Err("The selected image changed after verification. Choose it again.".into());
    }

    let targets = scan_targets(&handle)?;
    validate_write_target(
        &targets,
        &target_id,
        &confirmation,
        manifest.artifact.write_size,
    )?;
    Err(BRIDGE_UNAVAILABLE.into())
}

fn validate_write_target<'a>(
    targets: &'a [InstallTarget],
    target_id: &str,
    confirmation: &str,
    required_size: u64,
) -> Result<&'a InstallTarget, String> {
    let matches: Vec<_> = targets.iter().filter(|target| target.id == target_id).collect();
    if matches.len() != 1 {
        return Err("The selected drive is missing or no longer uniquely identified.".into());
    }
    let target = matches[0];
    if !target.removable || target.system || target.mounted || target.read_only {
        return Err("The selected drive is no longer safe to erase.".into());
    }
    if target.size_bytes < MINIMUM_TARGET_SIZE || target.size_bytes < required_size {
        return Err("The selected drive is too small for this image.".into());
    }
    let expected = format!(
        "ERASE {} — {} — {}",
        target.model, target.path, target.size_bytes
    );
    if confirmation != expected {
        return Err("The erase confirmation does not match the freshly inspected drive.".into());
    }
    Ok(target)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(InstallerState::default())
        .plugin(tauri_plugin_dialog::init())
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
    use super::{
        is_sha256, parse_inventory, validate_write_target, verify_cms_signature, InstallTarget,
    };
    use openssl::asn1::Asn1Time;
    use openssl::bn::BigNum;
    use openssl::cms::{CmsContentInfo, CMSOptions};
    use openssl::hash::MessageDigest;
    use openssl::pkey::PKey;
    use openssl::rsa::Rsa;
    use openssl::x509::extension::{BasicConstraints, ExtendedKeyUsage, KeyUsage};
    use openssl::x509::{X509NameBuilder, X509};

    #[test]
    fn accepts_shared_inventory_contract() {
        let targets = parse_inventory(br#"{"schema":1,"targets":[{"id":"linux:test","path":"/dev/test","model":"Test USB","size_bytes":8589934592,"removable":true,"system":false,"mounted":false,"read_only":false}]}"#).unwrap();
        assert_eq!(targets.len(), 1);
        assert_eq!(targets[0].model, "Test USB");
    }

    #[test]
    fn rejects_incomplete_inventory() {
        let error = parse_inventory(br#"{"schema":1,"targets":[{"id":"","path":"/dev/test","model":"Test USB","size_bytes":8589934592,"removable":true,"system":false,"mounted":false,"read_only":false}]}"#).unwrap_err();
        assert!(error.contains("incomplete"));
    }

    #[test]
    fn accepts_only_lowercase_sha256_values() {
        assert!(is_sha256(&"a".repeat(64)));
        assert!(!is_sha256(&"A".repeat(64)));
        assert!(!is_sha256(&"g".repeat(64)));
        assert!(!is_sha256(&"a".repeat(63)));
    }

    fn safe_target() -> InstallTarget {
        InstallTarget {
            id: "linux:test".into(),
            path: "/dev/test".into(),
            model: "Test USB".into(),
            size_bytes: 8 * 1024 * 1024 * 1024,
            removable: true,
            system: false,
            mounted: false,
            read_only: false,
        }
    }

    #[test]
    fn requires_exact_confirmation_for_fresh_target() {
        let target = safe_target();
        let phrase = format!("ERASE Test USB — /dev/test — {}", target.size_bytes);
        assert!(validate_write_target(&[target.clone()], "linux:test", &phrase, 1).is_ok());
        assert!(validate_write_target(&[target], "linux:test", "ERASE stale", 1).is_err());
    }

    #[test]
    fn rejects_system_target_and_insufficient_capacity() {
        let mut target = safe_target();
        let phrase = format!("ERASE Test USB — /dev/test — {}", target.size_bytes);
        target.system = true;
        assert!(validate_write_target(&[target.clone()], "linux:test", &phrase, 1).is_err());
        target.system = false;
        assert!(validate_write_target(
            &[target],
            "linux:test",
            &phrase,
            9 * 1024 * 1024 * 1024,
        )
        .is_err());
    }

    fn temporary_signer() -> (PKey<openssl::pkey::Private>, X509) {
        let key = PKey::from_rsa(Rsa::generate(2048).unwrap()).unwrap();
        let mut name = X509NameBuilder::new().unwrap();
        name.append_entry_by_text("CN", "Bedrock temporary test signer").unwrap();
        let name = name.build();
        let mut certificate = X509::builder().unwrap();
        certificate.set_version(2).unwrap();
        let serial = BigNum::from_u32(1).unwrap().to_asn1_integer().unwrap();
        certificate.set_serial_number(&serial).unwrap();
        certificate.set_subject_name(&name).unwrap();
        certificate.set_issuer_name(&name).unwrap();
        certificate.set_pubkey(&key).unwrap();
        certificate.set_not_before(&Asn1Time::days_from_now(0).unwrap()).unwrap();
        certificate.set_not_after(&Asn1Time::days_from_now(1).unwrap()).unwrap();
        certificate
            .append_extension(BasicConstraints::new().critical().ca().build().unwrap())
            .unwrap();
        certificate
            .append_extension(KeyUsage::new().digital_signature().key_cert_sign().build().unwrap())
            .unwrap();
        certificate
            .append_extension(ExtendedKeyUsage::new().email_protection().build().unwrap())
            .unwrap();
        certificate.sign(&key, MessageDigest::sha256()).unwrap();
        (key, certificate.build())
    }

    #[test]
    fn accepts_trusted_cms_and_rejects_changed_manifest() {
        let manifest = br#"{"schema":1}"#;
        let (key, certificate) = temporary_signer();
        let cms = CmsContentInfo::sign(
            Some(&certificate),
            Some(&key),
            None,
            Some(manifest),
            CMSOptions::BINARY | CMSOptions::DETACHED,
        )
        .unwrap();
        let signature = cms.to_der().unwrap();
        let trust = certificate.to_pem().unwrap();
        verify_cms_signature(manifest, &signature, &trust).unwrap();
        assert!(verify_cms_signature(b"changed", &signature, &trust).is_err());
        assert!(verify_cms_signature(manifest, &signature, b"").is_err());
    }
}
use openssl::cms::{CmsContentInfo, CMSOptions};
use openssl::x509::{store::X509StoreBuilder, X509};
