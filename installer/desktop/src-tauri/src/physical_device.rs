use crate::device_finalizer::{DeviceFinalizer, PlatformFinalizer};
use std::io::{self, Read, Seek, SeekFrom, Write};

#[cfg(target_os = "linux")]
pub struct PlatformPhysicalDevice {
    file: std::fs::File,
}

#[cfg(target_os = "linux")]
impl PlatformPhysicalDevice {
    pub fn from_exclusive_file(file: std::fs::File) -> Self {
        Self { file }
    }
}

#[cfg(target_os = "linux")]
impl Read for PlatformPhysicalDevice {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        self.file.read(buffer)
    }
}

#[cfg(target_os = "linux")]
impl Write for PlatformPhysicalDevice {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.file.write(buffer)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}

#[cfg(target_os = "linux")]
impl Seek for PlatformPhysicalDevice {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.file.seek(position)
    }
}

#[cfg(target_os = "linux")]
impl DeviceFinalizer for PlatformPhysicalDevice {
    fn synchronize_cache(&mut self) -> Result<(), String> {
        let mut finalizer = PlatformFinalizer::new(&self.file);
        finalizer.synchronize_cache()
    }

    fn try_eject(&mut self) -> Result<bool, String> {
        let mut finalizer = PlatformFinalizer::new(&self.file);
        finalizer.try_eject()
    }
}

#[cfg(target_os = "macos")]
pub struct PlatformPhysicalDevice {
    descriptor: i32,
}

#[cfg(target_os = "macos")]
impl PlatformPhysicalDevice {
    /// The descriptor must be the validated exclusive raw-disk descriptor.
    pub unsafe fn from_exclusive_descriptor(descriptor: i32) -> Self {
        Self { descriptor }
    }
}

#[cfg(target_os = "macos")]
impl Read for PlatformPhysicalDevice {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        let read = unsafe {
            libc::read(
                self.descriptor,
                buffer.as_mut_ptr().cast(),
                buffer.len(),
            )
        };
        if read < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(read as usize)
    }
}

#[cfg(target_os = "macos")]
impl Write for PlatformPhysicalDevice {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        let written = unsafe {
            libc::write(self.descriptor, buffer.as_ptr().cast(), buffer.len())
        };
        if written < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(written as usize)
    }

    fn flush(&mut self) -> io::Result<()> {
        if unsafe { libc::fsync(self.descriptor) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }
}

#[cfg(target_os = "macos")]
impl Seek for PlatformPhysicalDevice {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        let (offset, whence) = match position {
            SeekFrom::Start(offset) => (
                i64::try_from(offset).map_err(|_| {
                    io::Error::new(io::ErrorKind::InvalidInput, "seek position is too large")
                })?,
                libc::SEEK_SET,
            ),
            SeekFrom::Current(offset) => (offset, libc::SEEK_CUR),
            SeekFrom::End(offset) => (offset, libc::SEEK_END),
        };
        let new_position = unsafe { libc::lseek(self.descriptor, offset, whence) };
        if new_position < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(new_position as u64)
    }
}

#[cfg(target_os = "macos")]
impl DeviceFinalizer for PlatformPhysicalDevice {
    fn synchronize_cache(&mut self) -> Result<(), String> {
        let mut finalizer = unsafe {
            PlatformFinalizer::from_exclusive_descriptor(self.descriptor)
        };
        finalizer.synchronize_cache()
    }

    fn try_eject(&mut self) -> Result<bool, String> {
        let mut finalizer = unsafe {
            PlatformFinalizer::from_exclusive_descriptor(self.descriptor)
        };
        finalizer.try_eject()
    }
}

#[cfg(target_os = "macos")]
impl Drop for PlatformPhysicalDevice {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.descriptor);
        }
    }
}

#[cfg(target_os = "windows")]
pub struct PlatformPhysicalDevice {
    handle: windows_sys::Win32::Foundation::HANDLE,
}

#[cfg(target_os = "windows")]
impl PlatformPhysicalDevice {
    /// The handle must be the validated zero-share physical-drive handle.
    pub unsafe fn from_exclusive_handle(
        handle: windows_sys::Win32::Foundation::HANDLE,
    ) -> Self {
        Self { handle }
    }
}

#[cfg(target_os = "windows")]
impl Read for PlatformPhysicalDevice {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        use windows_sys::Win32::Storage::FileSystem::ReadFile;

        let length = buffer.len().min(u32::MAX as usize) as u32;
        let mut read = 0_u32;
        if unsafe {
            ReadFile(
                self.handle,
                buffer.as_mut_ptr().cast(),
                length,
                &mut read,
                std::ptr::null_mut(),
            )
        } == 0
        {
            return Err(io::Error::last_os_error());
        }
        Ok(read as usize)
    }
}

#[cfg(target_os = "windows")]
impl Write for PlatformPhysicalDevice {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        use windows_sys::Win32::Storage::FileSystem::WriteFile;

        let length = buffer.len().min(u32::MAX as usize) as u32;
        let mut written = 0_u32;
        if unsafe {
            WriteFile(
                self.handle,
                buffer.as_ptr().cast(),
                length,
                &mut written,
                std::ptr::null_mut(),
            )
        } == 0
        {
            return Err(io::Error::last_os_error());
        }
        Ok(written as usize)
    }

    fn flush(&mut self) -> io::Result<()> {
        use windows_sys::Win32::Storage::FileSystem::FlushFileBuffers;

        if unsafe { FlushFileBuffers(self.handle) } == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }
}

#[cfg(target_os = "windows")]
impl Seek for PlatformPhysicalDevice {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        use windows_sys::Win32::Storage::FileSystem::{
            SetFilePointerEx, FILE_BEGIN, FILE_CURRENT, FILE_END,
        };

        let (distance, method) = match position {
            SeekFrom::Start(offset) => (
                i64::try_from(offset).map_err(|_| {
                    io::Error::new(io::ErrorKind::InvalidInput, "seek position is too large")
                })?,
                FILE_BEGIN,
            ),
            SeekFrom::Current(offset) => (offset, FILE_CURRENT),
            SeekFrom::End(offset) => (offset, FILE_END),
        };
        let mut new_position = 0_i64;
        if unsafe { SetFilePointerEx(self.handle, distance, &mut new_position, method) } == 0 {
            return Err(io::Error::last_os_error());
        }
        u64::try_from(new_position).map_err(|_| {
            io::Error::new(io::ErrorKind::InvalidData, "device returned a negative position")
        })
    }
}

#[cfg(target_os = "windows")]
impl DeviceFinalizer for PlatformPhysicalDevice {
    fn synchronize_cache(&mut self) -> Result<(), String> {
        let mut finalizer = unsafe { PlatformFinalizer::from_exclusive_handle(self.handle) };
        finalizer.synchronize_cache()
    }

    fn try_eject(&mut self) -> Result<bool, String> {
        let mut finalizer = unsafe { PlatformFinalizer::from_exclusive_handle(self.handle) };
        finalizer.try_eject()
    }
}

#[cfg(target_os = "windows")]
impl Drop for PlatformPhysicalDevice {
    fn drop(&mut self) {
        unsafe {
            windows_sys::Win32::Foundation::CloseHandle(self.handle);
        }
    }
}
