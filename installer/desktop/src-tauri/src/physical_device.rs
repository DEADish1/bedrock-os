use crate::device_finalizer::{DeviceFinalizer, PlatformFinalizer};
use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom, Write};

pub struct LinuxPhysicalDevice {
    file: File,
}

impl LinuxPhysicalDevice {
    pub fn from_exclusive_file(file: File) -> Self {
        Self { file }
    }
}

impl Read for LinuxPhysicalDevice {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        self.file.read(buffer)
    }
}

impl Write for LinuxPhysicalDevice {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.file.write(buffer)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}

impl Seek for LinuxPhysicalDevice {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.file.seek(position)
    }
}

impl DeviceFinalizer for LinuxPhysicalDevice {
    fn synchronize_cache(&mut self) -> Result<(), String> {
        let mut finalizer = PlatformFinalizer::new(&self.file);
        finalizer.synchronize_cache()
    }

    fn try_eject(&mut self) -> Result<bool, String> {
        let mut finalizer = PlatformFinalizer::new(&self.file);
        finalizer.try_eject()
    }
}
