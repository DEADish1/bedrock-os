use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::File;
#[cfg(target_os = "linux")]
use std::fs::OpenOptions;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{path::BaseDirectory, Manager, State};
use tauri_plugin_dialog::DialogExt;
use uuid::Uuid;

mod media_writer;
mod device_finalizer;
mod write_pipeline;
#[cfg(any(target_os = "linux", target_os = "windows"))]
mod physical_device;

const RELEASE_TRUST_CERT_PEM: &[u8] =
    include_bytes!(concat!(env!("OUT_DIR"), "/bedrock-release-trust.pem"));

const BRIDGE_UNAVAILABLE: &str =
    "The protected disk service is not connected. No disk operation was attempted.";
const MINIMUM_TARGET_SIZE: u64 = 8 * 1024 * 1024 * 1024;
const MAX_HELPER_REQUEST_BYTES: u64 = 16 * 1024;
const HELPER_REQUEST_LIFETIME_SECONDS: u64 = 120;
const HELPER_PREFLIGHT_ONLY_EXIT: i32 = 3;
const HELPER_WRITE_COMPLETE_EXIT: i32 = 0;
const MACOS_APP_IDENTIFIER: &str = "os.bedrock.installer";
const MACOS_HELPER_IDENTIFIER: &str = "com.bedrock.server.installer.writer";
#[cfg(target_os = "macos")]
const APPLE_TEAM_ID: Option<&str> = option_env!("BEDROCK_APPLE_TEAM_ID");

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

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PrivilegedWriteRequest {
    schema: u8,
    session_id: String,
    requested_at: u64,
    image_path: PathBuf,
    target_id: String,
    confirmation: String,
}

#[derive(Debug)]
struct PreparedWrite {
    target: InstallTarget,
    image_path: PathBuf,
    image_type: String,
    write_size: u64,
    write_sha256: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ProtectedWriterResult {
    PreflightOnly,
    WriteComplete,
}

fn physical_writer_enabled() -> bool {
    cfg!(all(
        any(target_os = "linux", target_os = "windows"),
        bedrock_physical_writer
    ))
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
    let request = PrivilegedWriteRequest {
        schema: 1,
        session_id: session.public.session_id,
        requested_at: unix_time_seconds()?,
        image_path: session.image_path,
        target_id,
        confirmation,
    };
    match launch_protected_writer(&request)? {
        ProtectedWriterResult::WriteComplete => Ok(()),
        ProtectedWriterResult::PreflightOnly => Err(BRIDGE_UNAVAILABLE.into()),
    }
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

fn validate_helper_request(request: &PrivilegedWriteRequest, now: u64) -> Result<(), String> {
    if request.schema != 1
        || Uuid::parse_str(&request.session_id).is_err()
        || !request.image_path.is_absolute()
        || request.image_path.to_string_lossy().len() > 4096
        || request.target_id.is_empty()
        || request.target_id.len() > 512
        || request.confirmation.is_empty()
        || request.confirmation.len() > 1024
    {
        return Err("The protected writer request is invalid.".into());
    }
    if request.requested_at > now.saturating_add(30)
        || now.saturating_sub(request.requested_at) > HELPER_REQUEST_LIFETIME_SECONDS
    {
        return Err("The protected writer request has expired.".into());
    }
    Ok(())
}

fn unix_time_seconds() -> Result<u64, String> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .map_err(|_| "The protected writer could not validate the system clock.".to_string())
}

fn helper_request_bytes(request: &PrivilegedWriteRequest) -> Result<Vec<u8>, String> {
    let bytes = serde_json::to_vec(request)
        .map_err(|_| "The protected writer request could not be encoded.".to_string())?;
    if bytes.len() as u64 > MAX_HELPER_REQUEST_BYTES {
        return Err("The protected writer request is too large.".into());
    }
    Ok(bytes)
}

fn encode_helper_request(request: &PrivilegedWriteRequest) -> Result<String, String> {
    Ok(BASE64.encode(helper_request_bytes(request)?))
}

fn macos_peer_requirement(identifier: &str, team_id: Option<&str>) -> Result<String, String> {
    if identifier != MACOS_APP_IDENTIFIER && identifier != MACOS_HELPER_IDENTIFIER {
        return Err("The macOS code-signing identity is invalid.".into());
    }
    let team_id = team_id
        .filter(|value| {
            value.len() == 10
                && value
                    .bytes()
                    .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
        })
        .ok_or_else(|| {
            "This build has no trusted Apple Team ID. No disk operation was attempted.".to_string()
        })?;
    Ok(format!(
        "identifier \"{identifier}\" and anchor apple generic and certificate leaf[subject.OU] = \"{team_id}\""
    ))
}

fn decode_helper_request(encoded: &str) -> Result<Vec<u8>, String> {
    let maximum_encoded = (MAX_HELPER_REQUEST_BYTES as usize).div_ceil(3) * 4;
    if encoded.len() > maximum_encoded {
        return Err("The protected writer request is too large.".into());
    }
    let bytes = BASE64
        .decode(encoded)
        .map_err(|_| "The protected writer request encoding is invalid.".to_string())?;
    if bytes.len() as u64 > MAX_HELPER_REQUEST_BYTES {
        return Err("The protected writer request is too large.".into());
    }
    Ok(bytes)
}

fn validate_elevated_identity(elevated: bool) -> Result<(), String> {
    if elevated {
        Ok(())
    } else {
        Err(
            "The protected writer is not running with administrator authority. No disk operation was attempted."
                .into(),
        )
    }
}

#[cfg(target_os = "linux")]
fn whole_device_open_path(target: &InstallTarget) -> Result<PathBuf, String> {
    let path = Path::new(&target.path);
    if path.parent() != Some(Path::new("/dev"))
        || path.file_name().and_then(|name| name.to_str()).is_none()
    {
        return Err("The confirmed Linux target is not a direct device path.".into());
    }
    Ok(path.to_path_buf())
}

#[cfg(target_os = "macos")]
fn whole_device_open_path(target: &InstallTarget) -> Result<PathBuf, String> {
    let name = target
        .path
        .strip_prefix("/dev/disk")
        .filter(|suffix| !suffix.is_empty() && suffix.bytes().all(|byte| byte.is_ascii_digit()))
        .ok_or_else(|| "The confirmed macOS target is not a whole disk.".to_string())?;
    Ok(PathBuf::from(format!("/dev/rdisk{name}")))
}

#[cfg(target_os = "windows")]
fn whole_device_open_path(target: &InstallTarget) -> Result<PathBuf, String> {
    let number = target
        .path
        .strip_prefix(r"\\.\PhysicalDrive")
        .filter(|suffix| !suffix.is_empty() && suffix.bytes().all(|byte| byte.is_ascii_digit()))
        .ok_or_else(|| "The confirmed Windows target is not a whole physical drive.".to_string())?;
    Ok(PathBuf::from(format!(r"\\.\PhysicalDrive{number}")))
}

#[cfg(target_os = "linux")]
fn open_exclusive_whole_device(
    target: &InstallTarget,
) -> Result<crate::physical_device::PlatformPhysicalDevice, String> {
    use std::os::fd::AsRawFd;
    use std::os::unix::fs::{FileTypeExt, MetadataExt, OpenOptionsExt};

    const BLKGETSIZE64: libc::c_ulong = 0x8008_1272;
    let path = whole_device_open_path(target)?;
    let device = OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_CLOEXEC | libc::O_EXCL | libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(&path)
        .map_err(|_| "The confirmed Linux disk could not be opened exclusively.".to_string())?;
    let metadata = device
        .metadata()
        .map_err(|_| "The opened Linux disk identity could not be inspected.".to_string())?;
    if !metadata.file_type().is_block_device() {
        return Err("The confirmed Linux target is not a block device.".into());
    }
    let sysfs = PathBuf::from(format!(
        "/sys/dev/block/{}:{}",
        libc::major(metadata.rdev()),
        libc::minor(metadata.rdev())
    ));
    if !sysfs.is_dir()
        || sysfs
            .join("partition")
            .try_exists()
            .map_err(|_| "The Linux disk partition state could not be checked.".to_string())?
    {
        return Err(
            "The confirmed Linux target is a partition or has unknown device identity.".into(),
        );
    }
    let mut opened_size = 0_u64;
    if unsafe { libc::ioctl(device.as_raw_fd(), BLKGETSIZE64, &mut opened_size) } != 0
        || opened_size != target.size_bytes
    {
        return Err("The opened Linux disk capacity no longer matches the confirmed drive.".into());
    }
    Ok(crate::physical_device::PlatformPhysicalDevice::from_exclusive_file(device))
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn bedrock_macos_probe_exclusive_disk(path: *const core::ffi::c_char, size: u64) -> i32;
}

#[cfg(target_os = "macos")]
fn open_exclusive_whole_device(target: &InstallTarget) -> Result<(), String> {
    let path = whole_device_open_path(target)?;
    let path = std::ffi::CString::new(path.to_string_lossy().as_bytes())
        .map_err(|_| "The confirmed macOS disk path is invalid.".to_string())?;
    if unsafe { bedrock_macos_probe_exclusive_disk(path.as_ptr(), target.size_bytes) } != 0 {
        return Err(
            "The confirmed macOS disk could not be exclusively opened with the same capacity."
                .into(),
        );
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn open_exclusive_whole_device(
    target: &InstallTarget,
) -> Result<crate::physical_device::PlatformPhysicalDevice, String> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Foundation::{
        CloseHandle, GENERIC_READ, GENERIC_WRITE, INVALID_HANDLE_VALUE,
    };
    use windows_sys::Win32::Storage::FileSystem::{
        CreateFileW, FILE_FLAG_WRITE_THROUGH, OPEN_EXISTING,
    };
    use windows_sys::Win32::System::IO::DeviceIoControl;
    use windows_sys::Win32::System::Ioctl::{
        GET_LENGTH_INFORMATION, IOCTL_DISK_GET_LENGTH_INFO,
    };

    let path = whole_device_open_path(target)?;
    let wide: Vec<u16> = path
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    let handle = unsafe {
        CreateFileW(
            wide.as_ptr(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            std::ptr::null(),
            OPEN_EXISTING,
            FILE_FLAG_WRITE_THROUGH,
            std::ptr::null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        return Err("The confirmed Windows disk could not be opened exclusively.".into());
    }
    let mut length = GET_LENGTH_INFORMATION::default();
    let mut returned = 0_u32;
    let inspected = unsafe {
        DeviceIoControl(
            handle,
            IOCTL_DISK_GET_LENGTH_INFO,
            std::ptr::null(),
            0,
            std::ptr::addr_of_mut!(length).cast(),
            std::mem::size_of::<GET_LENGTH_INFORMATION>() as u32,
            &mut returned,
            std::ptr::null_mut(),
        )
    };
    if inspected == 0
        || returned != std::mem::size_of::<GET_LENGTH_INFORMATION>() as u32
        || length.Length < 0
        || length.Length as u64 != target.size_bytes
    {
        unsafe { CloseHandle(handle) };
        return Err("The opened Windows disk capacity no longer matches the confirmed drive.".into());
    }
    Ok(unsafe {
        crate::physical_device::PlatformPhysicalDevice::from_exclusive_handle(handle)
    })
}

#[cfg(unix)]
fn platform_is_elevated() -> bool {
    unsafe { libc::geteuid() == 0 }
}

#[cfg(target_os = "windows")]
fn platform_is_elevated() -> bool {
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::Security::{
        GetTokenInformation, TokenElevation, TOKEN_ELEVATION, TOKEN_QUERY,
    };
    use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

    let mut token = std::ptr::null_mut();
    if unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) } == 0 {
        return false;
    }
    let mut elevation = TOKEN_ELEVATION::default();
    let mut returned_size = 0_u32;
    let result = unsafe {
        GetTokenInformation(
            token,
            TokenElevation,
            std::ptr::addr_of_mut!(elevation).cast::<core::ffi::c_void>(),
            std::mem::size_of::<TOKEN_ELEVATION>() as u32,
            &mut returned_size,
        )
    };
    unsafe { CloseHandle(token) };
    result != 0
        && returned_size == std::mem::size_of::<TOKEN_ELEVATION>() as u32
        && elevation.TokenIsElevated != 0
}

#[cfg(all(unix, not(target_os = "macos")))]
fn linux_helper_command(encoded: &str) -> Command {
    let mut command = Command::new("/usr/bin/pkexec");
    command
        .arg("/usr/bin/bedrock-media-writer")
        .arg("--request-base64")
        .arg(encoded);
    command
}

#[cfg(all(unix, not(target_os = "macos")))]
fn launch_protected_writer(
    request: &PrivilegedWriteRequest,
) -> Result<ProtectedWriterResult, String> {
    let encoded = encode_helper_request(request)?;
    let status = linux_helper_command(&encoded)
        .status()
        .map_err(|_| "The Linux administrator approval service could not start.".to_string())?;
    match status.code() {
        Some(HELPER_WRITE_COMPLETE_EXIT) => Ok(ProtectedWriterResult::WriteComplete),
        Some(HELPER_PREFLIGHT_ONLY_EXIT) => Ok(ProtectedWriterResult::PreflightOnly),
        Some(126) | Some(127) => {
            Err("Administrator approval was cancelled or unavailable.".into())
        }
        _ => Err(
            "The protected writer rejected the request. No disk operation was attempted.".into(),
        ),
    }
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn bedrock_macos_send_writer_request(
        bytes: *const u8,
        length: usize,
        helper_requirement: *const core::ffi::c_char,
    ) -> i32;
    fn bedrock_macos_run_writer_service(
        client_requirement: *const core::ffi::c_char,
    ) -> i32;
}

#[cfg(target_os = "macos")]
fn launch_protected_writer(
    request: &PrivilegedWriteRequest,
) -> Result<ProtectedWriterResult, String> {
    let bytes = helper_request_bytes(request)?;
    let requirement = macos_peer_requirement(MACOS_HELPER_IDENTIFIER, APPLE_TEAM_ID)?;
    let requirement = std::ffi::CString::new(requirement)
        .map_err(|_| "The trusted macOS helper requirement is invalid.".to_string())?;
    let result = unsafe {
        bedrock_macos_send_writer_request(bytes.as_ptr(), bytes.len(), requirement.as_ptr())
    };
    match result {
        HELPER_WRITE_COMPLETE_EXIT => Ok(ProtectedWriterResult::WriteComplete),
        HELPER_PREFLIGHT_ONLY_EXIT => Ok(ProtectedWriterResult::PreflightOnly),
        4 => Err(
            "Approve Bedrock Installer in System Settings > General > Login Items, then try again. No disk operation was attempted."
                .into(),
        ),
        5 => Err(
            "The signed macOS protected service could not be registered. No disk operation was attempted."
                .into(),
        ),
        6 => Err(
            "The authenticated macOS protected service could not be reached. No disk operation was attempted."
                .into(),
        ),
        _ => Err(
            "The protected writer rejected the request. No disk operation was attempted.".into(),
        ),
    }
}

#[cfg(target_os = "windows")]
fn launch_protected_writer(
    request: &PrivilegedWriteRequest,
) -> Result<ProtectedWriterResult, String> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Foundation::{CloseHandle, WAIT_OBJECT_0};
    use windows_sys::Win32::System::Threading::{
        GetExitCodeProcess, WaitForSingleObject, INFINITE,
    };
    use windows_sys::Win32::UI::Shell::{
        ShellExecuteExW, SEE_MASK_NOASYNC, SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW,
    };
    use windows_sys::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

    fn wide(value: &std::ffi::OsStr) -> Vec<u16> {
        value.encode_wide().chain(std::iter::once(0)).collect()
    }

    let encoded = encode_helper_request(request)?;
    let executable = std::env::current_exe()
        .map_err(|_| "The installer executable location is unavailable.".to_string())?;
    let helper = executable
        .parent()
        .ok_or_else(|| "The installer executable location is invalid.".to_string())?
        .join("bedrock-media-writer.exe");
    if !helper.is_file() {
        return Err(
            "The protected Windows writer is not installed. No disk operation was attempted."
                .into(),
        );
    }

    let verb = wide(std::ffi::OsStr::new("runas"));
    let helper = wide(helper.as_os_str());
    let parameters = wide(std::ffi::OsStr::new(&format!("--request-base64 {encoded}")));
    let mut info: SHELLEXECUTEINFOW = unsafe { std::mem::zeroed() };
    info.cbSize = std::mem::size_of::<SHELLEXECUTEINFOW>() as u32;
    info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
    info.lpVerb = verb.as_ptr();
    info.lpFile = helper.as_ptr();
    info.lpParameters = parameters.as_ptr();
    info.nShow = SW_SHOWNORMAL;

    if unsafe { ShellExecuteExW(&mut info) } == 0 || info.hProcess.is_null() {
        return Err("Windows administrator approval was cancelled or unavailable.".into());
    }
    let wait = unsafe { WaitForSingleObject(info.hProcess, INFINITE) };
    let mut exit_code = 1_u32;
    let read_exit = unsafe { GetExitCodeProcess(info.hProcess, &mut exit_code) };
    unsafe { CloseHandle(info.hProcess) };
    if wait != WAIT_OBJECT_0 || read_exit == 0 {
        return Err("The protected Windows writer did not finish safely.".into());
    }
    match exit_code as i32 {
        HELPER_WRITE_COMPLETE_EXIT => Ok(ProtectedWriterResult::WriteComplete),
        HELPER_PREFLIGHT_ONLY_EXIT => Ok(ProtectedWriterResult::PreflightOnly),
        _ => Err(
            "The protected writer rejected the request. No disk operation was attempted.".into(),
        ),
    }
}

fn helper_adapter_path(executable: &Path) -> Result<PathBuf, String> {
    let executable_dir = executable
        .parent()
        .ok_or_else(|| "The protected writer location is invalid.".to_string())?;
    let adapter = platform_adapter_path();
    let candidates = [
        executable_dir.join(adapter),
        executable_dir.join("adapters").join(
            Path::new(adapter)
                .file_name()
                .ok_or_else(|| "The drive scanner name is invalid.".to_string())?,
        ),
        executable_dir.join("../Resources").join(adapter),
        executable_dir
            .join("../share/bedrock-installer")
            .join(adapter),
    ];
    candidates
        .into_iter()
        .find(|candidate| candidate.is_file())
        .ok_or_else(|| "The protected writer could not locate its packaged drive scanner.".into())
}

fn protected_writer_preflight<R: Read>(
    input: R,
    executable: &Path,
    now: u64,
) -> Result<PreparedWrite, String> {
    let mut request_bytes = Vec::new();
    input
        .take(MAX_HELPER_REQUEST_BYTES + 1)
        .read_to_end(&mut request_bytes)
        .map_err(|_| "The protected writer request could not be read.".to_string())?;
    if request_bytes.len() as u64 > MAX_HELPER_REQUEST_BYTES {
        return Err("The protected writer request is too large.".into());
    }
    let request: PrivilegedWriteRequest = serde_json::from_slice(&request_bytes)
        .map_err(|_| "The protected writer request format is invalid.".to_string())?;
    validate_helper_request(&request, now)?;

    let manifest = verify_signed_release(&request.image_path, RELEASE_TRUST_CERT_PEM)?;
    let targets = parse_inventory(&run_inventory_adapter(&helper_adapter_path(executable)?)?)?;
    let target = validate_write_target(
        &targets,
        &request.target_id,
        &request.confirmation,
        manifest.artifact.write_size,
    )?
    .clone();
    Ok(PreparedWrite {
        target,
        image_path: request.image_path,
        image_type: manifest.artifact.image_type,
        write_size: manifest.artifact.write_size,
        write_sha256: manifest.artifact.write_sha256,
    })
}

fn protected_writer_open_gate<R: Read>(input: R, executable: &Path, now: u64) -> Result<(), String> {
    let prepared = protected_writer_preflight(input, executable, now)?;
    let _exclusive_device = open_exclusive_whole_device(&prepared.target)?;
    Ok(())
}

#[cfg(all(
    any(target_os = "linux", target_os = "windows"),
    bedrock_physical_writer
))]
fn protected_writer_operation<R: Read>(
    input: R,
    executable: &Path,
    now: u64,
) -> Result<ProtectedWriterResult, String> {
    use crate::write_pipeline::write_verify_and_finalize;

    let prepared = protected_writer_preflight(input, executable, now)?;
    let mut source = File::open(&prepared.image_path)
        .map_err(|_| "The verified image could not be reopened for writing.".to_string())?;
    let mut device = open_exclusive_whole_device(&prepared.target)?;
    write_verify_and_finalize(
        &prepared.image_type,
        &mut source,
        &mut device,
        prepared.write_size,
        &prepared.write_sha256,
        |_, _| {},
    )?;
    Ok(ProtectedWriterResult::WriteComplete)
}

#[cfg(not(all(
    any(target_os = "linux", target_os = "windows"),
    bedrock_physical_writer
)))]
fn protected_writer_operation<R: Read>(
    input: R,
    executable: &Path,
    now: u64,
) -> Result<ProtectedWriterResult, String> {
    protected_writer_open_gate(input, executable, now)?;
    Ok(ProtectedWriterResult::PreflightOnly)
}

#[cfg(not(target_os = "macos"))]
pub fn run_protected_writer_helper() -> i32 {
    if let Err(error) = validate_elevated_identity(platform_is_elevated()) {
        eprintln!("{error}");
        return 1;
    }
    let now = match unix_time_seconds() {
        Ok(now) => now,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    let executable = match std::env::current_exe() {
        Ok(path) => path,
        Err(_) => {
            eprintln!("The protected writer executable could not be identified.");
            return 1;
        }
    };
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let result = match arguments.as_slice() {
        [] => protected_writer_operation(std::io::stdin().lock(), &executable, now),
        [flag, encoded] if flag == "--request-base64" => decode_helper_request(encoded)
            .and_then(|bytes| {
                protected_writer_operation(std::io::Cursor::new(bytes), &executable, now)
            }),
        _ => Err("The protected writer command line is invalid.".into()),
    };
    match result {
        Ok(ProtectedWriterResult::WriteComplete) => HELPER_WRITE_COMPLETE_EXIT,
        Ok(ProtectedWriterResult::PreflightOnly) => {
            eprintln!("{BRIDGE_UNAVAILABLE}");
            HELPER_PREFLIGHT_ONLY_EXIT
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

#[cfg(target_os = "macos")]
fn macos_preflight_request(bytes: &[u8]) -> i32 {
    if let Err(error) = validate_elevated_identity(platform_is_elevated()) {
        eprintln!("{error}");
        return 1;
    }
    let now = match unix_time_seconds() {
        Ok(now) => now,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    let executable = match std::env::current_exe() {
        Ok(path) => path,
        Err(_) => {
            eprintln!("The protected writer executable could not be identified.");
            return 1;
        }
    };
    match protected_writer_open_gate(std::io::Cursor::new(bytes), &executable, now) {
        Ok(()) => HELPER_PREFLIGHT_ONLY_EXIT,
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

#[cfg(target_os = "macos")]
#[no_mangle]
pub unsafe extern "C" fn bedrock_macos_handle_writer_request(
    bytes: *const u8,
    length: usize,
) -> i32 {
    if bytes.is_null() || length == 0 || length as u64 > MAX_HELPER_REQUEST_BYTES {
        return 1;
    }
    macos_preflight_request(unsafe { std::slice::from_raw_parts(bytes, length) })
}

#[cfg(target_os = "macos")]
pub fn run_protected_writer_helper() -> i32 {
    if let Err(error) = validate_elevated_identity(platform_is_elevated()) {
        eprintln!("{error}");
        return 1;
    }
    let requirement = match macos_peer_requirement(MACOS_APP_IDENTIFIER, APPLE_TEAM_ID)
        .and_then(|value| {
            std::ffi::CString::new(value)
                .map_err(|_| "The trusted macOS client requirement is invalid.".to_string())
        }) {
        Ok(requirement) => requirement,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    unsafe { bedrock_macos_run_writer_service(requirement.as_ptr()) }
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
        decode_helper_request, encode_helper_request, is_sha256, parse_inventory,
        macos_peer_requirement, protected_writer_preflight, validate_elevated_identity,
        physical_writer_enabled, validate_helper_request, validate_write_target,
        verify_cms_signature, whole_device_open_path, InstallTarget, PrivilegedWriteRequest,
        MACOS_APP_IDENTIFIER, MACOS_HELPER_IDENTIFIER,
    };
    use openssl::asn1::Asn1Time;
    use openssl::bn::BigNum;
    use openssl::cms::{CmsContentInfo, CMSOptions};
    use openssl::hash::MessageDigest;
    use openssl::pkey::PKey;
    use openssl::rsa::Rsa;
    use openssl::x509::extension::{BasicConstraints, ExtendedKeyUsage, KeyUsage};
    use openssl::x509::{X509NameBuilder, X509};
    use std::io::Cursor;
    use std::path::{Path, PathBuf};
    use uuid::Uuid;

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

    #[test]
    fn derives_only_platform_whole_device_paths() {
        let mut target = safe_target();
        #[cfg(target_os = "linux")]
        {
            target.path = "/dev/sdz".into();
            assert_eq!(
                whole_device_open_path(&target).unwrap(),
                PathBuf::from("/dev/sdz")
            );
            target.path = "/dev/disk/by-id/untrusted".into();
        }
        #[cfg(target_os = "macos")]
        {
            target.path = "/dev/disk42".into();
            assert_eq!(
                whole_device_open_path(&target).unwrap(),
                PathBuf::from("/dev/rdisk42")
            );
            target.path = "/dev/disk42s1".into();
        }
        #[cfg(target_os = "windows")]
        {
            target.path = r"\\.\PhysicalDrive42".into();
            assert_eq!(
                whole_device_open_path(&target).unwrap(),
                PathBuf::from(r"\\.\PhysicalDrive42")
            );
            target.path = r"\\.\C:".into();
        }
        assert!(whole_device_open_path(&target).is_err());
    }

    fn helper_request(requested_at: u64) -> PrivilegedWriteRequest {
        PrivilegedWriteRequest {
            schema: 1,
            session_id: Uuid::new_v4().to_string(),
            requested_at,
            image_path: absolute_test_image_path(),
            target_id: "linux:test".into(),
            confirmation: "ERASE Test USB — /dev/test — 8589934592".into(),
        }
    }

    #[cfg(target_os = "windows")]
    fn absolute_test_image_path() -> PathBuf {
        PathBuf::from(r"C:\releases\bedrock-os-amd64.iso")
    }

    #[cfg(not(target_os = "windows"))]
    fn absolute_test_image_path() -> PathBuf {
        PathBuf::from("/releases/bedrock-os-amd64.iso")
    }

    #[test]
    fn accepts_only_fresh_bounded_helper_requests() {
        assert!(validate_helper_request(&helper_request(1_000), 1_100).is_ok());
        assert!(validate_helper_request(&helper_request(1_000), 1_121).is_err());
        assert!(validate_helper_request(&helper_request(1_031), 1_000).is_err());

        let mut request = helper_request(1_000);
        request.image_path = PathBuf::from("bedrock-os-amd64.iso");
        assert!(validate_helper_request(&request, 1_000).is_err());

        let mut request = helper_request(1_000);
        request.target_id = "x".repeat(513);
        assert!(validate_helper_request(&request, 1_000).is_err());
    }

    #[test]
    fn helper_transport_round_trips_bounded_json() {
        let request = helper_request(1_000);
        let encoded = encode_helper_request(&request).unwrap();
        let decoded = decode_helper_request(&encoded).unwrap();
        let restored: PrivilegedWriteRequest = serde_json::from_slice(&decoded).unwrap();
        assert_eq!(restored.session_id, request.session_id);
        assert_eq!(restored.target_id, request.target_id);
        assert!(decode_helper_request("not base64!").is_err());
    }

    #[test]
    fn helper_requires_elevated_process_identity() {
        assert!(validate_elevated_identity(true).is_ok());
        let error = validate_elevated_identity(false).unwrap_err();
        assert!(error.contains("administrator authority"));
        assert!(error.contains("No disk operation was attempted"));
    }

    #[test]
    #[cfg(not(bedrock_physical_writer))]
    fn normal_build_keeps_physical_writing_disabled() {
        assert!(!physical_writer_enabled());
    }

    #[test]
    fn macos_peer_requirements_bind_identifier_and_team() {
        let requirement =
            macos_peer_requirement(MACOS_HELPER_IDENTIFIER, Some("A1B2C3D4E5")).unwrap();
        assert!(requirement.contains("identifier \"com.bedrock.server.installer.writer\""));
        assert!(requirement.contains("certificate leaf[subject.OU] = \"A1B2C3D4E5\""));
        assert!(macos_peer_requirement(MACOS_APP_IDENTIFIER, None).is_err());
        assert!(macos_peer_requirement(MACOS_APP_IDENTIFIER, Some("bad team!")).is_err());
        assert!(macos_peer_requirement("com.attacker.writer", Some("A1B2C3D4E5")).is_err());
    }

    #[cfg(all(unix, not(target_os = "macos")))]
    #[test]
    fn linux_transport_uses_only_exact_protected_paths() {
        let command = super::linux_helper_command("encoded-request");
        assert_eq!(command.get_program(), "/usr/bin/pkexec");
        let arguments: Vec<_> = command.get_args().collect();
        assert_eq!(
            arguments,
            [
                "/usr/bin/bedrock-media-writer",
                "--request-base64",
                "encoded-request"
            ]
        );
    }

    #[test]
    fn rejects_oversized_helper_input_before_processing() {
        let input = Cursor::new(vec![b'x'; 16 * 1024 + 1]);
        let error = protected_writer_preflight(input, Path::new("/bedrock/helper"), 1_000)
            .unwrap_err();
        assert!(error.contains("too large"));
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
