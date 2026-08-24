#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RemovalOutcome {
    Ejected,
    SafeForManualRemoval,
}

pub trait DeviceFinalizer {
    fn synchronize_cache(&mut self) -> Result<(), String>;
    fn try_eject(&mut self) -> Result<bool, String>;
}

pub fn finalize_written_device<T: DeviceFinalizer>(
    device: &mut T,
) -> Result<RemovalOutcome, String> {
    device.synchronize_cache()?;
    if device.try_eject()? {
        Ok(RemovalOutcome::Ejected)
    } else {
        Ok(RemovalOutcome::SafeForManualRemoval)
    }
}

#[cfg(target_os = "linux")]
pub struct PlatformFinalizer<'a> {
    device: &'a std::fs::File,
}

#[cfg(target_os = "linux")]
impl<'a> PlatformFinalizer<'a> {
    pub fn new(device: &'a std::fs::File) -> Self {
        Self { device }
    }
}

#[cfg(target_os = "linux")]
impl DeviceFinalizer for PlatformFinalizer<'_> {
    fn synchronize_cache(&mut self) -> Result<(), String> {
        use std::os::fd::AsRawFd;

        const BLKFLSBUF: libc::c_ulong = 0x1261;
        self.device
            .sync_all()
            .map_err(|_| "The Linux device could not be synchronized safely.".to_string())?;
        if unsafe { libc::ioctl(self.device.as_raw_fd(), BLKFLSBUF) } != 0 {
            return Err("The Linux block-device cache could not be flushed safely.".into());
        }
        Ok(())
    }

    fn try_eject(&mut self) -> Result<bool, String> {
        // Linux has no universal whole-disk eject ioctl for USB/SD media. Once
        // fsync and BLKFLSBUF succeed, the UI must instruct manual removal.
        Ok(false)
    }
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn bedrock_macos_synchronize_disk(descriptor: i32) -> i32;
    fn bedrock_macos_eject_disk(descriptor: i32) -> i32;
}

#[cfg(target_os = "macos")]
pub struct PlatformFinalizer {
    descriptor: i32,
}

#[cfg(target_os = "macos")]
impl PlatformFinalizer {
    /// The descriptor must be the validated exclusive raw-disk descriptor.
    pub unsafe fn from_exclusive_descriptor(descriptor: i32) -> Self {
        Self { descriptor }
    }
}

#[cfg(target_os = "macos")]
impl DeviceFinalizer for PlatformFinalizer {
    fn synchronize_cache(&mut self) -> Result<(), String> {
        if unsafe { bedrock_macos_synchronize_disk(self.descriptor) } != 0 {
            return Err("The macOS device cache could not be synchronized safely.".into());
        }
        Ok(())
    }

    fn try_eject(&mut self) -> Result<bool, String> {
        Ok(unsafe { bedrock_macos_eject_disk(self.descriptor) } == 0)
    }
}

#[cfg(target_os = "windows")]
pub struct PlatformFinalizer {
    handle: windows_sys::Win32::Foundation::HANDLE,
}

#[cfg(target_os = "windows")]
impl PlatformFinalizer {
    /// The handle must be the validated zero-share physical-drive handle.
    pub unsafe fn from_exclusive_handle(
        handle: windows_sys::Win32::Foundation::HANDLE,
    ) -> Self {
        Self { handle }
    }
}

#[cfg(target_os = "windows")]
impl DeviceFinalizer for PlatformFinalizer {
    fn synchronize_cache(&mut self) -> Result<(), String> {
        use windows_sys::Win32::Storage::FileSystem::FlushFileBuffers;

        if unsafe { FlushFileBuffers(self.handle) } == 0 {
            return Err("The Windows device cache could not be synchronized safely.".into());
        }
        Ok(())
    }

    fn try_eject(&mut self) -> Result<bool, String> {
        use windows_sys::Win32::System::IO::DeviceIoControl;
        use windows_sys::Win32::System::Ioctl::{
            IOCTL_STORAGE_EJECT_MEDIA, IOCTL_STORAGE_MEDIA_REMOVAL, PREVENT_MEDIA_REMOVAL,
        };

        let mut returned = 0_u32;
        let allow_removal = PREVENT_MEDIA_REMOVAL {
            PreventMediaRemoval: 0,
        };
        let allowed = unsafe {
            DeviceIoControl(
                self.handle,
                IOCTL_STORAGE_MEDIA_REMOVAL,
                std::addr_of!(allow_removal).cast(),
                std::mem::size_of::<PREVENT_MEDIA_REMOVAL>() as u32,
                std::ptr::null_mut(),
                0,
                &mut returned,
                std::ptr::null_mut(),
            )
        };
        if allowed == 0 {
            return Ok(false);
        }
        let ejected = unsafe {
            DeviceIoControl(
                self.handle,
                IOCTL_STORAGE_EJECT_MEDIA,
                std::ptr::null(),
                0,
                std::ptr::null_mut(),
                0,
                &mut returned,
                std::ptr::null_mut(),
            )
        };
        Ok(ejected != 0)
    }
}

#[cfg(test)]
mod tests {
    use super::{finalize_written_device, DeviceFinalizer, RemovalOutcome};

    struct RecordingFinalizer {
        calls: Vec<&'static str>,
        flush_succeeds: bool,
        ejects: bool,
    }

    impl DeviceFinalizer for RecordingFinalizer {
        fn synchronize_cache(&mut self) -> Result<(), String> {
            self.calls.push("synchronize");
            if self.flush_succeeds {
                Ok(())
            } else {
                Err("simulated flush failure".into())
            }
        }

        fn try_eject(&mut self) -> Result<bool, String> {
            self.calls.push("eject");
            Ok(self.ejects)
        }
    }

    #[test]
    fn synchronizes_before_ejecting() {
        let mut device = RecordingFinalizer {
            calls: Vec::new(),
            flush_succeeds: true,
            ejects: true,
        };
        assert_eq!(
            finalize_written_device(&mut device).unwrap(),
            RemovalOutcome::Ejected
        );
        assert_eq!(device.calls, ["synchronize", "eject"]);
    }

    #[test]
    fn reports_safe_manual_removal_when_eject_is_unsupported() {
        let mut device = RecordingFinalizer {
            calls: Vec::new(),
            flush_succeeds: true,
            ejects: false,
        };
        assert_eq!(
            finalize_written_device(&mut device).unwrap(),
            RemovalOutcome::SafeForManualRemoval
        );
        assert_eq!(device.calls, ["synchronize", "eject"]);
    }

    #[test]
    fn never_ejects_after_a_failed_synchronization() {
        let mut device = RecordingFinalizer {
            calls: Vec::new(),
            flush_succeeds: false,
            ejects: true,
        };
        assert!(finalize_written_device(&mut device).is_err());
        assert_eq!(device.calls, ["synchronize"]);
    }
}
