# Bedrock Installer

This directory contains the cross-platform installer foundation. The graphical Windows, macOS, and Linux application will call a small privileged writer only after the unprivileged selection layer validates an exact removable target.

## Safety boundary

`core/validate-target-selection.sh` consumes a fresh JSON inventory snapshot and returns the selected target only when all release-blocking rules pass. It never writes to a disk.

```sh
sh installer/core/validate-target-selection.sh inventory.json target-id "ERASE model — path — capacity"
```

Platform adapters must provide stable target IDs and refresh the inventory immediately before privileged writing. See `docs/INSTALLER-SAFETY.md`.

`core/verify-signed-image.sh` is the mandatory pre-write trust gate. It validates the CMS signature against the bundled Bedrock release certificate, enforces the canonical manifest schema and requested filename, and verifies exact image size and SHA-256.

`core/write-verified-image.sh` revalidates the exact target and confirmation, requires a whole block device and administrator privileges in production, writes a verified hybrid ISO or expands a signed raw Zstandard image, flushes it, rereads the written byte range, and requires the signed expanded SHA-256 before reporting success.

The desktop package now also contains a platform-neutral native streaming engine for the protected helper. It writes ISO or compressed raw content, reports byte progress, rejects short or oversized streams, flushes, rereads the exact signed range, and requires the signed expanded SHA-256. It is not connected to a physical target until the OS-specific elevation and whole-disk opening layer is complete.

`desktop/src-tauri/src/bin/bedrock-media-writer.rs` is the separate protected-helper entry point. Its bounded, time-limited request contains no caller-selected target path. The normal app can now send that request through exact-path Linux `pkexec` or native Windows `runas`, while macOS remains unavailable pending its signed SMAppService/XPC peer. The helper independently verifies the image, resolves only its packaged drive scanner, refreshes inventory, and repeats target selection before stopping at the disabled physical-device boundary.

## Platform adapters

- `adapters/linux-list-targets.sh` reads Linux block-device metadata without elevation, identifies the disk containing `/`, and emits the shared schema. If the system disk cannot be identified, every target is marked as a system disk and writing remains blocked.
- `adapters/macos-list-targets.sh` uses read-only `diskutil` property lists to identify whole disks, the macOS system disk, removable/ejectable media, mounted partitions, capacity, and read-only state.
- `adapters/windows-list-targets.ps1` uses read-only Windows Storage cmdlets to identify physical disks, boot/system disks, USB/SD/MMC media, mounted partitions, capacity, and read-only state.

## Graphical shell

`ui/` contains the shared responsive installer interface. It exposes no direct disk commands and can only request `choose_and_verify_image`, `list_targets`, and `write_verified_image` through the desktop bridge. The confirmation button remains disabled until the exact generated phrase matches.

`desktop/` packages that interface with Tauri 2 for Windows, macOS, and Linux. Its capability file grants only core window permissions and its content-security policy blocks unapproved web content. Read-only drive discovery calls only the packaged platform adapter. The native chooser verifies strict manifest, filename, size, SHA-256, and detached CMS trust against a build-injected public certificate. The trusted local path stays in native memory while the interface receives only an opaque session ID. Every write request repeats image verification, refreshes drive inventory, and validates the exact erase phrase and capacity before reaching the still-disabled privileged writer. Development builds without a trust anchor reject every image.
