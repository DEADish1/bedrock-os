# Bedrock Installer

This directory contains the cross-platform installer foundation. The graphical Windows, macOS, and Linux application will call a small privileged writer only after the unprivileged selection layer validates an exact removable target.

## Safety boundary

`core/validate-target-selection.sh` consumes a fresh JSON inventory snapshot and returns the selected target only when all release-blocking rules pass. It never writes to a disk.

```sh
sh installer/core/validate-target-selection.sh inventory.json target-id "ERASE model — path — capacity"
```

Platform adapters must provide stable target IDs and refresh the inventory immediately before privileged writing. See `docs/INSTALLER-SAFETY.md`.

`core/verify-signed-image.sh` is the mandatory pre-write trust gate. It validates the CMS signature against the bundled Bedrock release certificate, enforces the canonical manifest schema and requested filename, and verifies exact image size and SHA-256.

`core/write-verified-image.sh` revalidates the exact target and confirmation, requires a whole block device and administrator privileges in production, writes only a verified hybrid ISO, flushes it, rereads the written byte range, and requires the signed SHA-256 before reporting success.

## Platform adapters

- `adapters/linux-list-targets.sh` reads Linux block-device metadata without elevation, identifies the disk containing `/`, and emits the shared schema. If the system disk cannot be identified, every target is marked as a system disk and writing remains blocked.
- `adapters/macos-list-targets.sh` uses read-only `diskutil` property lists to identify whole disks, the macOS system disk, removable/ejectable media, mounted partitions, capacity, and read-only state.
- `adapters/windows-list-targets.ps1` uses read-only Windows Storage cmdlets to identify physical disks, boot/system disks, USB/SD/MMC media, mounted partitions, capacity, and read-only state.
