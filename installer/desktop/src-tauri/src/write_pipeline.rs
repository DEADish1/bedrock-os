use crate::device_finalizer::{finalize_written_device, DeviceFinalizer, RemovalOutcome};
use crate::media_writer::write_verified_media;
use std::io::{Read, Seek, Write};

pub trait MediaDevice: Read + Write + Seek + DeviceFinalizer {}

impl<T> MediaDevice for T where T: Read + Write + Seek + DeviceFinalizer {}

pub fn write_verify_and_finalize<R, D, F>(
    image_type: &str,
    source: &mut R,
    device: &mut D,
    expected_size: u64,
    expected_sha256: &str,
    progress: F,
) -> Result<RemovalOutcome, String>
where
    R: Read,
    D: MediaDevice,
    F: FnMut(u64, u64),
{
    write_verified_media(
        image_type,
        source,
        device,
        expected_size,
        expected_sha256,
        progress,
    )?;
    finalize_written_device(device)
}

#[cfg(test)]
mod tests {
    use super::write_verify_and_finalize;
    use crate::device_finalizer::{DeviceFinalizer, RemovalOutcome};
    use sha2::{Digest, Sha256};
    use std::io::{self, Cursor, Read, Seek, SeekFrom, Write};

    struct VirtualDevice {
        bytes: Cursor<Vec<u8>>,
        finalization: Vec<&'static str>,
        synchronize_succeeds: bool,
        ejects: bool,
    }

    impl VirtualDevice {
        fn new(size: usize) -> Self {
            Self {
                bytes: Cursor::new(vec![0_u8; size]),
                finalization: Vec::new(),
                synchronize_succeeds: true,
                ejects: true,
            }
        }
    }

    impl Read for VirtualDevice {
        fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
            self.bytes.read(buffer)
        }
    }

    impl Write for VirtualDevice {
        fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
            self.bytes.write(buffer)
        }

        fn flush(&mut self) -> io::Result<()> {
            self.bytes.flush()
        }
    }

    impl Seek for VirtualDevice {
        fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
            self.bytes.seek(position)
        }
    }

    impl DeviceFinalizer for VirtualDevice {
        fn synchronize_cache(&mut self) -> Result<(), String> {
            self.finalization.push("synchronize");
            if self.synchronize_succeeds {
                Ok(())
            } else {
                Err("simulated cache synchronization failure".into())
            }
        }

        fn try_eject(&mut self) -> Result<bool, String> {
            self.finalization.push("eject");
            Ok(self.ejects)
        }
    }

    fn sha256(bytes: &[u8]) -> String {
        format!("{:x}", Sha256::digest(bytes))
    }

    #[test]
    fn completes_verified_iso_on_one_virtual_device() {
        let image = b"Bedrock end-to-end virtual ISO".repeat(4096);
        let mut source = Cursor::new(image.clone());
        let mut device = VirtualDevice::new(image.len());
        let mut progress = (0, 0);
        let outcome = write_verify_and_finalize(
            "iso",
            &mut source,
            &mut device,
            image.len() as u64,
            &sha256(&image),
            |written, total| progress = (written, total),
        )
        .unwrap();

        assert_eq!(outcome, RemovalOutcome::Ejected);
        assert_eq!(progress, (image.len() as u64, image.len() as u64));
        assert_eq!(&device.bytes.get_ref()[..image.len()], image);
        assert_eq!(device.finalization, ["synchronize", "eject"]);
    }

    #[test]
    fn completes_compressed_raw_with_manual_removal_result() {
        let image = b"Bedrock end-to-end virtual raw image".repeat(4096);
        let compressed = zstd::stream::encode_all(&image[..], 1).unwrap();
        let mut source = Cursor::new(compressed);
        let mut device = VirtualDevice::new(image.len());
        device.ejects = false;
        let outcome = write_verify_and_finalize(
            "raw-zst",
            &mut source,
            &mut device,
            image.len() as u64,
            &sha256(&image),
            |_, _| {},
        )
        .unwrap();

        assert_eq!(outcome, RemovalOutcome::SafeForManualRemoval);
        assert_eq!(&device.bytes.get_ref()[..image.len()], image);
        assert_eq!(device.finalization, ["synchronize", "eject"]);
    }

    #[test]
    fn verification_failure_never_reaches_finalization() {
        let image = b"Bedrock changed virtual image".repeat(4096);
        let mut source = Cursor::new(image.clone());
        let mut device = VirtualDevice::new(image.len());
        let error = write_verify_and_finalize(
            "iso",
            &mut source,
            &mut device,
            image.len() as u64,
            &"0".repeat(64),
            |_, _| {},
        )
        .unwrap_err();

        assert!(error.contains("checksum"));
        assert!(device.finalization.is_empty());
    }

    #[test]
    fn synchronization_failure_never_attempts_eject() {
        let image = b"Bedrock virtual synchronization failure".repeat(4096);
        let mut source = Cursor::new(image.clone());
        let mut device = VirtualDevice::new(image.len());
        device.synchronize_succeeds = false;
        let error = write_verify_and_finalize(
            "iso",
            &mut source,
            &mut device,
            image.len() as u64,
            &sha256(&image),
            |_, _| {},
        )
        .unwrap_err();

        assert!(error.contains("synchronization"));
        assert_eq!(device.finalization, ["synchronize"]);
    }
}
