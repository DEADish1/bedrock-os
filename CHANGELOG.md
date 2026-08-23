# Bedrock Server OS update log

This file records completed work, decisions, validation, and the next starting point. Update it whenever work is completed or a release state changes.

## Unreleased

### Next starting point

- Boot-test the v0.2 image on physical Intel and AMD systems and the remaining common VM platforms.
- Implement the v0.4 RAID management service: safe array/pool creation, health adapters, rebuild progress, replacement, and recovery tests.
- Add update download/resume transport, release-channel policy, and certificate-rotation handling.

### Bootable foundation work

- Added a defined v0.2 boot-test matrix, privacy-safe report format, and fail-closed validator for VMware, Hyper-V, and physical Intel/AMD acceptance evidence.
- Passed the reproducible-build release gate in GitHub Actions run `32644096736`: two independent Debian 13 builders produced byte-identical ISOs with identical package locks and build manifests.
- Passed the complete raw-disk validation suite in the same run, including signed artifact verification, UEFI boot, good-update promotion, bad-update exhaustion, and automatic rollback.
- Made release timestamps and source revisions explicit inside isolated builders instead of relying on inaccessible mounted Git metadata.
- Made live initramfs generation independent of AMD-versus-Intel build-host hardware by always including both supported CPU microcode families.
- Removed transient DNS, NVMe identity, download-history, random-seed, and package-cache state before sealing the image; disabled regenerated APT caches at the source.
- Marked the v0.2 reproducible CI requirement complete; v0.2 now has seven of eight requirements complete.
- Added the Debian 13 `live-build` configuration under `os/`.
- Added a sorted baseline package list for boot, networking, hardware discovery, drive health, and recovery tooling.
- Added deterministic build inputs using `SOURCE_DATE_EPOCH`, a release environment file, and a source-derived build manifest.
- Added ISO checksum generation and artifact verification scripts.
- Added a GitHub Actions workflow for clean Debian 13 builds, artifact upload, and build-provenance attestation.
- Validated shell syntax, configuration invariants, package ordering, duplicate detection, and workflow YAML locally.
- Added the machine-readable amd64 GPT layout for UEFI, root A/B, dm-verity hash/signature pairs, and persistent state.
- Added a validated three-attempt health-gated promotion and automatic rollback policy.
- Added layout invariants covering partition order, unique labels, standard type GUIDs, mutability, capacity, and recovery behavior.
- Added the verified-boot command line and a fail-closed UKI builder that binds each slot to its dm-verity root hash.
- Required protected Secure Boot signing material and added validation that rejects ambiguous label-based root selection.
- Added deterministic EROFS root-image creation, detached dm-verity tree generation, PKCS#7 root-hash signing, and signature-partition JSON generation.
- Added an artifact verifier that checks both the root filesystem integrity tree and signature authenticity before disk assembly.
- Added raw GPT disk assembly driven by the machine-readable layout, with deterministic partition identifiers and both verified A/B slots.
- Added EFI fallback boot installation, systemd-boot configuration, persistent-state formatting, raw-image checksums, and GPT structure verification.
- Added a boot-health service that verifies writable persistent state, atomically records the last-good slot, and blesses the boot only after checks pass.
- Added an OVMF/QEMU test harness that fails unless the expected A/B slot reaches the explicit healthy-boot marker.
- Wired the immutable roots, signed UKIs, GPT assembly, and UEFI health test into one opt-in end-to-end raw-image build.
- Added explicit ephemeral CI development-key generation and a signing manifest that prevents test-key artifacts from being treated as releases.
- Ran the first full amd64 Linux build locally in an isolated native Linux volume; Debian bootstrap and Bedrock package installation completed.
- Replaced the chroot's `systemd-boot` management package with binary-only `systemd-boot-efi` after the real build exposed an invalid EFI-install trigger during live ISO assembly.
- Corrected the live-build image-name contract after the successful retry produced a duplicated `amd64-amd64` architecture suffix.
- Added the host-side `systemd-boot-efi` dependency after UKI creation proved that `systemd-ukify` does not itself provide the required EFI stub.
- Removed loop-device and mount dependencies from raw-disk assembly after Docker Desktop did not expose partition devices; assembly now writes at verified GPT offsets and uses offline filesystem tools.
- Fixed raw-image checksum manifests to store the portable artifact filename rather than the caller's relative or absolute build path.
- Made slot A the explicit factory default and routed kernel diagnostics to the serial console after the first OVMF boot selected slot B by filename order and timed out without actionable kernel output.
- The diagnostic boot reached Debian's BusyBox initramfs and proved that the live-media initramfs cannot discover the installed signed root without an explicit root device.
- Split the boot paths: the ISO retains live-boot, while raw installed images now use a dedicated systemd/dracut initramfs.
- Replaced unsupported `root=dissect` handling in Debian 13's dracut with slot-bound dm-verity data/hash partition identifiers embedded in each signed UKI.
- Mounted `/proc`, `/sys`, and `/dev` while generating the installed initramfs and added the required systemd verity module.
- Added the persistent `/var` mount contract and a pre-created EFI mount point to the immutable root.
- Added three-attempt counted UKI filenames and slot-aware health blessing that commits the persistent health record before promoting only the running entry.
- Completed the OVMF/QEMU acceptance boot: slot A activated its verified EROFS root, mounted writable state, recorded health, blessed its boot entry, and emitted the exact healthy-slot marker.
- Added a non-destructive A/B rollback harness that corrupts only a disposable slot-A copy, preserves UEFI variables across restarts, and verifies every counted filename transition.
- Confirmed all three failed slot-A attempts decrement from `+3` through `+0-3` without producing a healthy marker.
- Found and resolved a selector defect in Debian 13's systemd-boot 257: a configured default ignores the exhausted-entry assessment. Bedrock now omits the forced default and ranks factory UKIs by `IMAGE_VERSION`, allowing the built-in zero-attempt ordering to select healthy B.
- Passed the complete rollback acceptance gate: three corrupted slot-A boots exhausted `+3` to `+0-3`, the fourth unattended boot selected slot B, B mounted verified root and persistent state, emitted its healthy marker, and was promoted.
- Wired the rollback acceptance harness into every opt-in raw-image build before the normal healthy-A smoke test.
- Added canonical signed update manifests containing the release version, monotonic image generation, architecture, and exact size/SHA-256 records for the root, verity tree, verity signature, and UKI.
- Added fail-closed bundle verification against the immutable OS trust certificate, including strict schema/file allowlisting and tamper detection.
- Added the privileged inactive-slot installer with mounted-slot refusal, partition-capacity checks, post-write hashing, three-attempt UKI arming, and pending-generation state.
- Extended boot-health promotion to commit an update generation only after the newly installed slot reaches writable persistent state and is blessed.
- Added a signed-bundle regression test that accepts valid content and rejects a one-byte artifact change; wired it into the image build.
- Added an explicitly test-only raw-disk target to the production updater so Docker-based CI can exercise exact GPT partition writes without unsafe host device access.
- Passed the full-disk good-update gate: installed signed generation 3 into inactive B, read back and verified every write, armed the counted UKI, booted B automatically as the newer generation, and reached its healthy marker.
- Wired the signed full-disk installation/boot test into every opt-in raw-image build.
- Generalized the rollback harness so either A or B can be the failed candidate while the opposite slot remains the required healthy fallback.
- Passed the signed bad-update gate: the updater accepted an intentionally unbootable but correctly signed generation into inactive B, B failed and decremented exactly three times, and the fourth unattended boot recovered to healthy A.
- Marked the signed manifest and rollback-capable updater roadmap requirement complete after both good-update promotion and bad-update recovery passed on disposable full GPT images.
- Added a boot-time hardware inventory service that records CPU topology and virtualization, total RAM, physical disks, non-loopback network interfaces, and DRM GPUs in a stable JSON contract on persistent state.
- Added Intel, AMD, and NVIDIA GPU recognition with kernel-driver and IOMMU-group reporting for later passthrough eligibility checks.
- Made boot health wait for inventory collection and added deterministic discovery fixtures covering CPU, memory, disk, and network output.
- Marked the v0.2 hardware-discovery requirement complete after its schema and service-enablement acceptance checks passed.
- Added a two-replica GitHub Actions build matrix: replica one runs the complete raw-image/boot suite while both replicas produce independent clean ISOs.
- Added a fail-closed reproducibility comparator requiring byte-identical ISOs, identical resolved package locks, and identical build manifests.
- Added regression coverage proving the comparator accepts matching builds and rejects a changed image.
- Kept reproducible CI builds open because `DEADish1/bedrock-os` does not yet exist and the available signed GitHub browser session requires login before repository creation.
- Changed the normal UEFI smoke test to boot a disposable image copy so validation can no longer promote or otherwise mutate release artifacts.

### Installer and first-run work

- Defined the cross-platform installer disk-inventory and privileged-writer safety boundary.
- Added a fail-closed target-selection validator that rejects system, internal, mounted, read-only, undersized, missing, ambiguous, and incorrectly confirmed disks.
- Added regression fixtures covering the safe removable-drive path and destructive-selection rejection cases.
- Added the Linux removable-drive inventory adapter with root-disk, mounted-media, read-only, capacity, model, and path reporting.
- Added fixture-based Linux enumeration tests, including fail-closed behavior when the system disk cannot be identified.
- Added the macOS removable-drive adapter using read-only `diskutil` property lists, including mounted-partition and system-disk detection.
- Added macOS enumeration fixtures and the same unknown-system-disk fail-closed acceptance test.
- Added the Windows physical-drive adapter using read-only Storage cmdlets, with boot/system, mounted-volume, removable-bus, capacity, and read-only detection.
- Added PowerShell fixture coverage for safe USB selection and unknown-system-disk fail-closed behavior.
- Added a canonical signed installer-image manifest for ISO and compressed raw USB artifacts.
- Added a mandatory pre-write verifier for certificate trust, strict schema and filename matching, exact size, and SHA-256.
- Added regression tests proving valid signed media is accepted while modified images, unexpected names, and modified manifests are rejected.
- Added the guarded hybrid-ISO media writer with target revalidation, administrator/block-device enforcement, capacity checks, flushed writes, full reread, and signed SHA-256 verification.
- Added disposable-file regression coverage for successful write/verify, incorrect destructive confirmation, and insufficient target capacity.

### Architecture decisions

- Defined RAID support: OpenZFS mirror/RAID-Z as the preferred software path, Linux MD RAID 1/5/6/10 compatibility, and tested hardware RAID logical volumes with honest limited-health status when member telemetry is unavailable.
- Added `mdadm`, LVM, and SCSI/SAS inspection tools to the Bedrock image baseline and added PCI storage/RAID controller discovery to hardware inventory schema 2.
- Added explicit software/hardware RAID status and contextual explanations to the Storage prototype and expanded the v0.4 checklist with controller-health and rebuild workflows.
- Approved amd64/UEFI as the Bedrock 1.0 host platform; ARM64 is deferred to a named-device program after 1.0.
- Selected Debian 13 stable with a release-pinned kernel and immutable, dm-verity-protected A/B system images.
- Selected OpenZFS, Samba, KVM/QEMU, libvirt, OVMF, and VFIO for storage and virtualization.
- Selected a restricted Rust core service, versioned API, SQLite metadata, and shared React/TypeScript UI.
- Selected Tauri 2 for signed Windows/macOS clients, WireGuard tunnels for remote access, and OpenID Connect with PKCE for optional Google identity.
- Added `docs/HARDWARE-SUPPORT.md` and `docs/ARCHITECTURE.md` as the reviewable support and architecture contracts.

## 0.1.0 — 2026-08-22

### Added

- Interactive Bedrock Server OS dashboard prototype.
- NAS/storage health, capacity, physical-drive, and quick-action surfaces.
- VM list, running-state controls, and CPU/RAM/GPU/image resource-selection flow.
- ISO and disk-image library concept supporting ISO, IMG, QCOW2, VHDX, and VMDK.
- Bedrock Installer download and boot-media creation concept.
- Windows/macOS Bedrock Client concept with QR/manual pairing and trusted devices.
- Optional Google sign-in concept with server approval and privacy explanation.
- Contextual keyboard-focusable `(?)` explanations.
- Bedrock brand package: official marks, dark hardware palette, typography, favicon, and social card.
- Responsive scaling corrections for desktop and narrow app panes.
- Versioned project roadmap through 1.0.0 and update-log process.

### Changed

- Renamed the prototype from Haven to Bedrock Server OS.
- Preserved the existing private prototype URL while updating product metadata.
- Increased text, metric, card, and control sizes for readability.
- Changed the intermediate-width layout to remove the compressed icon rail and reflow content.

### Validated

- Production build completes successfully.
- Dashboard visually checked at full desktop width and 655 px narrow width.
- Private deployment is available at the current project URL.

### Known limitations

- Current screens use prototype data and do not control a real server.
- Download buttons do not yet distribute bootable images, installers, or desktop clients.
- QR pairing and Google sign-in demonstrate the intended flow but have no production backend.
- GitHub release repositories and signed artifacts have not been created.
