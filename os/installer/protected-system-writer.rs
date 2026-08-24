use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{FileTypeExt, MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::process::{self, Command, Stdio};

const COPY_BUFFER_BYTES: usize = 1024 * 1024;
const BLKGETSIZE64: std::ffi::c_ulong = 0x8008_1272;
const O_EXCL: i32 = 0o200;
const O_NONBLOCK: i32 = 0o4000;
const O_NOFOLLOW: i32 = 0o400000;

unsafe extern "C" {
    fn geteuid() -> u32;
    fn ioctl(fd: i32, request: std::ffi::c_ulong, ...) -> i32;
}

fn fail(message: &str) -> ! {
    eprintln!("error: {message}");
    process::exit(1);
}

fn parse_decimal(value: &str, label: &str) -> u64 {
    value
        .parse::<u64>()
        .ok()
        .filter(|parsed| *parsed > 0)
        .unwrap_or_else(|| fail(&format!("{label} is invalid")))
}

fn validate_sha256(value: &str) -> String {
    if value.len() != 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        fail("the expected installation-image checksum is invalid");
    }
    value.to_owned()
}

fn direct_device_path(value: &str) -> PathBuf {
    let path = Path::new(value);
    if path.parent() != Some(Path::new("/dev"))
        || path.file_name().and_then(|name| name.to_str()).is_none()
    {
        fail("the confirmed target is not a direct Linux device path");
    }
    path.to_owned()
}

fn linux_major(device: u64) -> u64 {
    ((device >> 8) & 0xfff) | ((device >> 32) & 0xfffff000)
}

fn linux_minor(device: u64) -> u64 {
    (device & 0xff) | ((device >> 12) & 0xffffff00)
}

fn open_verified_source(path: &Path, expected_size: u64, expected_hash: &str) -> Result<File, String> {
    let path_metadata = fs::symlink_metadata(path)
        .map_err(|_| "the packaged installation image is unavailable".to_string())?;
    if !path_metadata.file_type().is_file() || path_metadata.file_type().is_symlink() {
        return Err("the packaged installation image is indirect or not a regular file".into());
    }

    let mut source = File::open(path)
        .map_err(|_| "the packaged installation image could not be opened".to_string())?;
    let opened_metadata = source
        .metadata()
        .map_err(|_| "the opened installation image could not be inspected".to_string())?;
    if !opened_metadata.file_type().is_file() || opened_metadata.len() != expected_size {
        return Err("the opened installation image size changed after preflight".into());
    }

    let source_for_hash = source
        .try_clone()
        .map_err(|_| "the opened installation image could not be rechecked".to_string())?;
    let output = Command::new("/usr/bin/sha256sum")
        .arg("-")
        .stdin(Stdio::from(source_for_hash))
        .output()
        .map_err(|_| "the fixed checksum verifier could not be executed".to_string())?;
    if !output.status.success() {
        return Err("the opened installation image checksum could not be calculated".into());
    }
    let actual_hash = String::from_utf8(output.stdout)
        .ok()
        .and_then(|line| line.split_whitespace().next().map(str::to_owned))
        .ok_or_else(|| "the checksum verifier returned an invalid result".to_string())?;
    if actual_hash != expected_hash {
        return Err("the opened installation image changed after preflight".into());
    }
    source
        .seek(SeekFrom::Start(0))
        .map_err(|_| "the verified installation image could not be rewound".to_string())?;
    Ok(source)
}

#[cfg(bedrock_system_physical_writer)]
fn open_exclusive_target(path: &Path, expected_capacity: u64) -> Result<(File, u64, u64), String> {
    let target = OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(O_EXCL | O_NONBLOCK | O_NOFOLLOW)
        .open(path)
        .map_err(|_| "the confirmed system disk could not be opened exclusively".to_string())?;
    let metadata = target
        .metadata()
        .map_err(|_| "the opened system disk could not be inspected".to_string())?;
    if !metadata.file_type().is_block_device() {
        return Err("the confirmed system target is not a block device".into());
    }
    let sysfs = PathBuf::from(format!(
        "/sys/dev/block/{}:{}",
        linux_major(metadata.rdev()),
        linux_minor(metadata.rdev())
    ));
    if !sysfs.is_dir() || sysfs.join("partition").exists() {
        return Err("the confirmed system target is a partition or has unknown identity".into());
    }

    let mut opened_capacity = 0_u64;
    if unsafe { ioctl(target.as_raw_fd(), BLKGETSIZE64, &mut opened_capacity) } != 0
        || opened_capacity != expected_capacity
    {
        return Err("the exclusively opened disk capacity no longer matches confirmation".into());
    }
    Ok((
        target,
        linux_major(metadata.rdev()),
        linux_minor(metadata.rdev()),
    ))
}

fn copy_flush_and_reread(
    source: &mut File,
    target: &mut File,
    expected_size: u64,
) -> Result<(), String> {
    source
        .seek(SeekFrom::Start(0))
        .map_err(|_| "the verified source could not be rewound".to_string())?;
    target
        .seek(SeekFrom::Start(0))
        .map_err(|_| "the system disk could not be positioned for writing".to_string())?;

    let mut buffer = vec![0_u8; COPY_BUFFER_BYTES];
    let mut written = 0_u64;
    while written < expected_size {
        let wanted = usize::try_from((expected_size - written).min(COPY_BUFFER_BYTES as u64))
            .map_err(|_| "the remaining write size is invalid".to_string())?;
        source
            .read_exact(&mut buffer[..wanted])
            .map_err(|_| "the verified source ended before the expected size".to_string())?;
        target
            .write_all(&buffer[..wanted])
            .map_err(|_| "the protected system-disk write was interrupted".to_string())?;
        written += wanted as u64;
    }
    let mut extra = [0_u8; 1];
    if source
        .read(&mut extra)
        .map_err(|_| "the verified source could not be bounded".to_string())?
        != 0
    {
        return Err("the verified source is larger than its confirmed size".into());
    }
    target
        .sync_all()
        .map_err(|_| "the system disk could not be synchronized after writing".to_string())?;

    source
        .seek(SeekFrom::Start(0))
        .and_then(|_| target.seek(SeekFrom::Start(0)))
        .map_err(|_| "the written system disk could not be positioned for verification".to_string())?;
    let mut source_buffer = vec![0_u8; COPY_BUFFER_BYTES];
    let mut target_buffer = vec![0_u8; COPY_BUFFER_BYTES];
    let mut verified = 0_u64;
    while verified < expected_size {
        let wanted = usize::try_from((expected_size - verified).min(COPY_BUFFER_BYTES as u64))
            .map_err(|_| "the remaining verification size is invalid".to_string())?;
        source
            .read_exact(&mut source_buffer[..wanted])
            .map_err(|_| "the source could not be reread".to_string())?;
        target
            .read_exact(&mut target_buffer[..wanted])
            .map_err(|_| "the system disk could not be fully reread".to_string())?;
        if source_buffer[..wanted] != target_buffer[..wanted] {
            return Err("the installed system image failed full reread verification".into());
        }
        verified += wanted as u64;
    }
    Ok(())
}

#[cfg(bedrock_system_physical_writer)]
fn run_physical_writer() -> Result<(), String> {
    if unsafe { geteuid() } != 0 {
        return Err("the protected system writer requires root authority".into());
    }
    let arguments: Vec<String> = env::args().collect();
    if arguments.len() != 6 {
        return Err(
            "usage: bedrock-system-writer SOURCE.raw TARGET CAPACITY SOURCE_SIZE SHA256".into(),
        );
    }
    let source_path = Path::new(&arguments[1]);
    let target_path = direct_device_path(&arguments[2]);
    let expected_capacity = parse_decimal(&arguments[3], "the confirmed disk capacity");
    let expected_size = parse_decimal(&arguments[4], "the confirmed image size");
    let expected_hash = validate_sha256(&arguments[5]);
    if expected_capacity < expected_size {
        return Err("the confirmed system disk is smaller than the installation image".into());
    }

    let mut source = open_verified_source(source_path, expected_size, &expected_hash)?;
    let (mut target, device_major, device_minor) =
        open_exclusive_target(&target_path, expected_capacity)?;
    copy_flush_and_reread(&mut source, &mut target, expected_size)?;
    println!(
        "{{\"schema\":1,\"raw_write_complete\":true,\"reread_verified\":true,\"device_major\":{device_major},\"device_minor\":{device_minor},\"layout_finalized\":false}}"
    );
    Ok(())
}

#[cfg(not(bedrock_system_physical_writer))]
fn run_physical_writer() -> Result<(), String> {
    Err("this build cannot open or write a physical system disk".into())
}

fn main() {
    if let Err(message) = run_physical_writer() {
        fail(&message);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn copy_is_fully_reread() {
        let root = env::temp_dir().join(format!("bedrock-system-writer-{}", process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir(&root).unwrap();
        let source_path = root.join("source.raw");
        let target_path = root.join("target.raw");
        let content = vec![0x5a_u8; COPY_BUFFER_BYTES + 137];
        fs::write(&source_path, &content).unwrap();
        fs::write(&target_path, vec![0_u8; content.len() + 4096]).unwrap();
        let mut source = OpenOptions::new().read(true).open(&source_path).unwrap();
        let mut target = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&target_path)
            .unwrap();
        copy_flush_and_reread(&mut source, &mut target, content.len() as u64).unwrap();
        let written = fs::read(&target_path).unwrap();
        assert_eq!(&written[..content.len()], content.as_slice());
        assert!(written[content.len()..].iter().all(|byte| *byte == 0));
        fs::remove_dir_all(root).unwrap();
    }
}
