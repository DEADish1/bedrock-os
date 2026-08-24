use sha2::{Digest, Sha256};
use std::io::{Read, Seek, SeekFrom, Write};

const BUFFER_SIZE: usize = 1024 * 1024;

pub fn write_verified_media<R, T, F>(
    image_type: &str,
    source: &mut R,
    target: &mut T,
    expected_size: u64,
    expected_sha256: &str,
    mut progress: F,
) -> Result<(), String>
where
    R: Read,
    T: Read + Write + Seek,
    F: FnMut(u64, u64),
{
    if expected_size == 0 || !is_sha256(expected_sha256) {
        return Err("The signed write identity is invalid.".into());
    }
    match image_type {
        "iso" => write_stream(
            source,
            target,
            expected_size,
            expected_sha256,
            &mut progress,
        ),
        "raw-zst" => {
            let mut decoded = zstd::stream::read::Decoder::new(source)
                .map_err(|_| "The compressed raw image could not be opened.".to_string())?;
            write_stream(
                &mut decoded,
                target,
                expected_size,
                expected_sha256,
                &mut progress,
            )
        }
        _ => Err("The image type is not supported by the native writer.".into()),
    }
}

fn write_stream<R, T, F>(
    source: &mut R,
    target: &mut T,
    expected_size: u64,
    expected_sha256: &str,
    progress: &mut F,
) -> Result<(), String>
where
    R: Read,
    T: Read + Write + Seek,
    F: FnMut(u64, u64),
{
    target
        .seek(SeekFrom::Start(0))
        .map_err(|_| "The target could not be positioned for writing.".to_string())?;
    let mut buffer = vec![0_u8; BUFFER_SIZE];
    let mut written = 0_u64;
    loop {
        let read = source
            .read(&mut buffer)
            .map_err(|_| "The image could not be read completely.".to_string())?;
        if read == 0 {
            break;
        }
        written = written
            .checked_add(read as u64)
            .ok_or_else(|| "The image write size overflowed.".to_string())?;
        if written > expected_size {
            return Err("The image expanded beyond its signed write size.".into());
        }
        target
            .write_all(&buffer[..read])
            .map_err(|_| "The media write was interrupted or incomplete.".to_string())?;
        progress(written, expected_size);
    }
    if written != expected_size {
        return Err("The image ended before its signed write size.".into());
    }
    target
        .flush()
        .map_err(|_| "The written media could not be flushed safely.".to_string())?;

    target
        .seek(SeekFrom::Start(0))
        .map_err(|_| "The written media could not be reopened for verification.".to_string())?;
    let mut remaining = expected_size;
    let mut digest = Sha256::new();
    while remaining > 0 {
        let limit = remaining.min(BUFFER_SIZE as u64) as usize;
        let read = target
            .read(&mut buffer[..limit])
            .map_err(|_| "The written media could not be reread completely.".to_string())?;
        if read == 0 {
            return Err("The written media ended before verification completed.".into());
        }
        digest.update(&buffer[..read]);
        remaining -= read as u64;
    }
    if format!("{:x}", digest.finalize()) != expected_sha256 {
        return Err("The written media checksum does not match the signed release.".into());
    }
    Ok(())
}

fn is_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

#[cfg(test)]
mod tests {
    use super::write_verified_media;
    use sha2::{Digest, Sha256};
    use std::io::{self, Cursor, Read, Seek, SeekFrom, Write};

    struct FailingTarget {
        inner: Cursor<Vec<u8>>,
        fail_after: u64,
    }

    impl Read for FailingTarget {
        fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
            self.inner.read(buffer)
        }
    }

    impl Write for FailingTarget {
        fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
            let position = self.inner.position();
            if position >= self.fail_after {
                return Err(io::Error::new(io::ErrorKind::Other, "simulated interruption"));
            }
            let allowed = (self.fail_after - position).min(buffer.len() as u64) as usize;
            self.inner.write(&buffer[..allowed])
        }

        fn flush(&mut self) -> io::Result<()> {
            self.inner.flush()
        }
    }

    impl Seek for FailingTarget {
        fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
            self.inner.seek(position)
        }
    }

    fn sha256(bytes: &[u8]) -> String {
        format!("{:x}", Sha256::digest(bytes))
    }

    #[test]
    fn writes_and_rereads_iso_with_progress() {
        let image = b"verified Bedrock ISO".repeat(4096);
        let mut source = Cursor::new(image.clone());
        let mut target = Cursor::new(vec![0_u8; image.len()]);
        let mut last_progress = (0, 0);
        write_verified_media(
            "iso",
            &mut source,
            &mut target,
            image.len() as u64,
            &sha256(&image),
            |written, total| last_progress = (written, total),
        )
        .unwrap();
        assert_eq!(&target.into_inner()[..image.len()], image);
        assert_eq!(last_progress, (image.len() as u64, image.len() as u64));
    }

    #[test]
    fn expands_and_verifies_compressed_raw_image() {
        let image = b"verified Bedrock raw image".repeat(4096);
        let compressed = zstd::stream::encode_all(&image[..], 1).unwrap();
        let mut source = Cursor::new(compressed);
        let mut target = Cursor::new(vec![0_u8; image.len()]);
        write_verified_media(
            "raw-zst",
            &mut source,
            &mut target,
            image.len() as u64,
            &sha256(&image),
            |_, _| {},
        )
        .unwrap();
        assert_eq!(&target.into_inner()[..image.len()], image);
    }

    #[test]
    fn rejects_short_oversized_and_mismatched_media() {
        let image = b"Bedrock image".to_vec();
        let hash = sha256(&image);

        let mut short_source = Cursor::new(image.clone());
        let mut short_target = Cursor::new(vec![0_u8; image.len() + 1]);
        assert!(write_verified_media(
            "iso",
            &mut short_source,
            &mut short_target,
            image.len() as u64 + 1,
            &hash,
            |_, _| {},
        )
        .is_err());

        let mut large_source = Cursor::new(image.clone());
        let mut large_target = Cursor::new(vec![0_u8; image.len()]);
        assert!(write_verified_media(
            "iso",
            &mut large_source,
            &mut large_target,
            image.len() as u64 - 1,
            &hash,
            |_, _| {},
        )
        .is_err());

        let mut changed_source = Cursor::new(image.clone());
        let mut changed_target = Cursor::new(vec![0_u8; image.len()]);
        assert!(write_verified_media(
            "iso",
            &mut changed_source,
            &mut changed_target,
            image.len() as u64,
            &"0".repeat(64),
            |_, _| {},
        )
        .is_err());
    }

    #[test]
    fn rejects_an_interrupted_target_write() {
        let image = b"Bedrock image that cannot finish".to_vec();
        let mut source = Cursor::new(image.clone());
        let mut target = FailingTarget {
            inner: Cursor::new(vec![0_u8; image.len()]),
            fail_after: 8,
        };
        let error = write_verified_media(
            "iso",
            &mut source,
            &mut target,
            image.len() as u64,
            &sha256(&image),
            |_, _| {},
        )
        .unwrap_err();
        assert!(error.contains("interrupted or incomplete"));
    }
}
