# Bedrock Server OS update log

This file records completed work, decisions, validation, and the next starting point. Update it whenever work is completed or a release state changes.

## Unreleased

### Virtual machines and images 0.5

- Added the packaged QEMU/KVM, libvirt system, and OVMF foundation plus a boot-time fail-closed capability report that distinguishes CPU virtualization, `/dev/kvm`, QEMU, firmware, and libvirt-system availability. VM mutation remains disabled until lifecycle policy and acceptance are implemented.

### Update delivery

- Restored clean-build ISO reproducibility after a Debian DKMS change began generating a random, unenrolled MOK: development images now remove the unusable appended module signatures and volatile DKMS/host identity state, with production module-key injection remaining a release-signing gate.
- Added bounded one-or-two-certificate update trust bundles, validated at build and before every CMS check, plus a tested current/next overlap and retirement procedure that rejects unrelated, duplicate, expired, malformed, indirect, and oversized trust inputs.
- Added immutable packaged stable/beta endpoints, schema-2 channel policy, explicit beta risk acknowledgement, channel-change recheck requirements, and stable-channel prerelease rejection without changing the no-automatic-install rule.
- Added a verified update download transport that resumes partial artifacts, rejects indirect paths and changed signed metadata, repairs corrupt completed files, atomically promotes only exact-size SHA-256 matches, verifies the complete signed bundle, and never installs automatically.

### Storage and NAS 0.4

- Added guarded OpenZFS mirror/RAID-Z and Linux RAID 1/5/6/10 creation, protected-vdev expansion, scrub/check, export/import, and failed-disk replacement workflows with exact destructive confirmation, fresh whole-disk checks, exclusive mutation locking, and durable audit state.
- Added a terminal-free local-console storage wizard with contextual protection explanations, healthy-disk selection, exact review, safe cancellation, and independently repeated privileged checks.
- Added persistent boot activation for managed Linux RAID storage and ordering that brings pools online before SMB/NFS services.
- Added users, groups, membership, plaintext-free Samba credential rotation, datasets, ZFS quotas, ACLs, manual snapshots, SMB/NFS shares, recycle behavior, and quota-required Time Machine shares.
- Added atomic Samba/NFS configuration rendering on persistent state for the immutable OS, SMB2.1 minimum, no guest mapping, and a storage-ordered Samba service override.
- Added StorCLI normalization for hardware RAID controller, physical-member, logical-volume, cache-protection, and rebuild health plus actionable alerts; unsupported controllers remain explicitly limited.
- Added bounded dataset SHA-256 manifests and recovery tests for interrupted operations, degraded pools, member replacement, rebuild/check, export/import, and corruption detection.
- Added a dedicated disposable Linux acceptance workflow that exercises real OpenZFS, Linux RAID, Samba parsing, failure, replacement, import, and post-recovery integrity without using host disks.
- Passed [Storage and NAS acceptance run #1](https://github.com/DEADish1/bedrock-os/actions/runs/33016715779): the real disposable OpenZFS/Linux RAID recovery job and every protected/guided storage and NAS contract completed without skips.
- Marked all ten v0.4 storage and NAS checklist items complete. Physical controller qualification remains model-specific, and abrupt-power hardware soak remains part of the v0.9 release-candidate gate.

### Physical acceptance preparation

- Added an on-image two-boot collector for VMware, Hyper-V Generation 2, physical Intel, and physical AMD acceptance. It verifies UEFI and Secure Boot state, exact platform DMI, x86-64 CPU/memory/disk/network inventory, a healthy marker tied to the running kernel boot ID, and a different healthy boot before emitting schema-2 evidence.
- Generated boot reports contain only the strict privacy-safe allowlist. The collector rejects virtual DMI presented as physical hardware, wrong VMware/Hyper-V identity, incomplete inventory, stale health state, missing UEFI variables, reuse without reboot, and indirect output paths.
- Added a non-destructive desktop evidence-workspace helper that binds the six acceptance report slots to one verified image SHA-256, rejects image changes and indirect inputs, shows missing or invalid sessions, and invokes the final bundle gate only after every role passes.
- Added a manual-only, seven-day desktop acceptance-kit job. After the two image replicas and boot/rollback suite pass, it verifies the exact protected-writer image is development-signed and non-release-eligible, signs the ISO with a fresh ephemeral media trust chain, builds a matching guarded Linux desktop writer, and bundles the runbooks and final validators without authorizing any device write.

### Desktop installer packaging

- Added a Tauri 2 desktop packaging shell for the shared Windows, macOS, and Linux installer interface.
- Restricted the desktop window to three typed installer commands with a strict content-security policy and no general shell access.
- Kept all native disk handlers fail-closed until the protected platform services are connected and verified.
- Aligned native drive and image response fields with the graphical interface contract.
- Added independent Windows, macOS, and Linux compile checks for the desktop package.
- Added the official Bedrock application icon required by native package compilation.
- Added a multi-resolution Windows icon resource generated from the same approved Bedrock artwork.
- Connected the desktop client to bundled read-only Windows, macOS, and Linux removable-drive inventory adapters.
- Added native inventory schema validation and Rust tests that reject malformed or incomplete drive records.
- Replaced the Windows adapter's modern-only hashing calls with Windows PowerShell 5.1-compatible cryptography APIs.
- Added native image selection without granting direct filesystem or dialog permissions to the web interface.
- Added fail-closed manifest, filename, signature-presence, exact-size, and streaming SHA-256 preflight validation.
- Corrected Windows helper elevation packaging so its UAC manifest replaces the helper resource after linking without conflicting with the unprivileged desktop-app manifest.
- Kept image acceptance disabled until the production trust certificate and native CMS validation are installed.
- Added native detached-CMS validation backed by a build-injected public release certificate.
- Made certificate-free development builds reject every image and production-mode builds fail at compile time when the trust certificate is missing.
- Added generated in-memory signature tests proving trusted manifests pass while changed manifests and missing trust anchors fail.
- Kept verified image paths inside native memory and exposed only opaque verification-session IDs to the interface.
- Added a pre-writer gate that repeats signed-image verification, refreshes removable-drive inventory, and revalidates safety, capacity, identity, and the exact erase phrase. The privileged writer remains disabled.
- Aligned the native drive response with the shared snake-case inventory contract so the interface reliably filters read-only media and displays exact capacity.
- Added a platform-neutral native media engine with ISO and compressed-raw streaming, bounded size checks, byte progress, flush, full reread, and signed SHA-256 verification.
- Marked the completed v0.3 removable-drive enumeration, signed-image verification, and exact destructive-confirmation checklist items complete.
- Added a separate fail-closed media-writer helper entry point with bounded, strict, time-limited requests, independent signed-image verification, packaged-scanner resolution, fresh inventory, and repeated target validation.
- Added release-only helper staging with target-triple naming and SHA-256 copy verification, helper-only Windows UAC metadata, exact-path Linux polkit policy, and macOS 13+ signed-bundle launch-daemon placement.
- Connected bounded protected-helper requests through exact-path Linux `pkexec` and native Windows `runas`, including process completion and a dedicated preflight-only exit code; macOS remains fail-closed pending signed SMAppService/XPC peer validation.
- Required the protected helper to prove effective UID 0 on Unix/macOS or an elevated Windows process token before reading any request.
- Added macOS 13+ SMAppService launch-daemon registration and privileged XPC request transport with mutual signing-identifier/Team-ID requirements, a production Team-ID gate, and fixed-identifier helper signing before staging.
- Added a fail-closed whole-device open gate: Linux rejects partitions through sysfs and uses exclusive no-follow block-device access, Windows opens exact physical drives with no sharing, and macOS takes an exclusive raw-disk lock; every platform confirms capacity and closes the handle without writing.
- Added a platform finalization layer that requires successful cache synchronization before eject, supports Windows storage eject and macOS disk eject, and reports synchronized Linux or unsupported eject media as safe for manual removal without claiming automatic ejection.
- Added an end-to-end virtual-device pipeline covering verified ISO and compressed-raw writing, progress, reread identity, cache synchronization, eject/manual-removal outcomes, and fail-closed checksum and synchronization errors without accessing host media.
- Added an explicitly destructive Linux disposable-drive acceptance runner with fresh inventory, whole/removable-device checks, exact path/capacity attestations, conservative large-drive protection, and privacy-safe evidence that cannot be confused with fixture results.
- Added fixture-tested Windows and macOS disposable-drive preflight gates with native inventory, exact whole-device/path/capacity/confirmation checks, destructive and large-drive attestations, and an explicit disabled-writer plan result.
- Added an acceptance-only Linux native device adapter connecting one exclusive handle through verified write, reread, synchronization, and finalization behind an exact production-trust build token; normal builds remain preflight-only and completed writes use a distinct helper result.
- Added the equivalent acceptance-only Windows adapter, retaining one zero-share `PhysicalDrive` handle through streaming, reread verification, cache flush, allow-removal, eject/manual-removal handling, and final close; CI compiles the gated branch without executing it.
- Added the acceptance-only macOS adapter, retaining one exclusive raw-disk descriptor through streaming, reread verification, full cache synchronization, eject, and final close; the authenticated XPC handler returns completed-write status only in an exact-token production build, and CI compiles without executing the branch.
- Added a versioned, session-bound, monotonic installer progress contract, real write/reread/finalization pipeline phases, and truthful graphical preparation/approval/completion states; privileged byte-progress relay remains fail-closed pending authenticated per-platform channels.
- Connected Linux protected-helper byte progress through a one-way pipe from the exact policy-bound executable, with strict session, size, sequence, phase, byte, and line validation; invalid display updates cannot affect the write and completion still requires a successful helper exit.
- Connected Windows protected-helper byte progress through a local-only inbound named pipe authenticated against the elevated helper process ID, with an interruptible connection wait, exact session-derived pipe identity, the shared strict progress validation, and successful helper exit still required for completion.
- Connected macOS protected-helper byte progress through a progress-only proxy object on the existing mutually code-signed XPC connection, with bounded messages, locked callback invalidation, shared session/size/sequence/phase validation, and successful protected-service completion still required.
- Added tested installer recovery guidance for insufficient space, interrupted writes, checksum failure, unavailable media, administrator approval, malformed progress, and unknown failures; failed media remains visibly untrusted and can be restarted safely.
- Added in-app and written USB/DVD guidance that distinguishes verified image burning from copying an ISO file and makes clear that optical writing and physical-hardware acceptance are not yet complete.
- Added the non-writing on-server installation foundation: live-media source protection, exact internal-drive confirmation, system/removable/mounted/read-only/undersized/ambiguous rejection, canonical-layout checksum binding, and a review-only plan that cannot claim writer readiness.
- Added a focused pull-request safety gate for Linux live-media discovery, the canonical system-disk layout, and non-writing installation-plan validation.
- Added a test-only on-server installation simulator that verifies the source, writes and rereads a confined sparse file, relocates GPT metadata, expands and checks persistent state, preserves fixed system content, and rejects interruption, corruption, outside-directory targets, and all non-test use.
- Added a bounded, expiring protected system-install request and independent preflight that fixes artifact/package/layout discovery, refreshes target inventory, rejects schema and identity changes, rechecks packaged image integrity and capacity, and still refuses to open a disk or claim writer readiness.
- Added a disabled-by-default Linux physical system-writer stage with an exact production-trust build gate, root and direct-whole-device enforcement, exclusive no-follow opening, kernel capacity recheck, opened-source SHA-256 verification, synchronized raw writing, and full byte-for-byte reread. Ordinary validation cannot execute or open it; GPT/state finalization and real-device acceptance were still unfinished at this checkpoint.
- Connected the post-write Linux finalizer to the kernel identity returned by the exclusive writer rather than a reusable device path. It uses private root-only device nodes, relocates and validates GPT, preserves the state partition GUID/type/name, rediscovers partition 8 through sysfs, grows and checks ext4, synchronizes it, and verifies all eight canonical partition roles. The live package set now includes the required GPT and ext4 tools. A gated Linux acceptance test executes the writer/finalizer only on a loop device proven to be backed by its disposable sparse file, then checks the detached image; real disposable-disk installation/boot evidence remains required.
- Added reproducible protected-installer staging for the live OS with fixed installed paths, scanner-fixture environment clearing, exact component checksums, build-mode metadata, cleanup after `live-build`, and runtime package-integrity/production-enabled checks. Development images remain fail-closed; production helper builds still require the exact destructive token and production-trust gate.
- Added an explicit manual protected-writer acceptance-image mode. The completed ISO is inspected to verify its embedded installer manifest and build mode, and the top-level build manifest records whether the system writer is enabled. Acceptance artifacts retain development signing and cannot be represented as release-eligible.
- Added the first functional first-run preference step for software updates. Users can enable scheduled signed-metadata checks or choose manual-only operation, change that choice later, and run Check now even while automatic checks are off. The persistent policy defaults off until a choice is recorded; disabled timer runs make no network request, checks never install automatically, and invalid or tampered metadata cannot replace the last verified result.
- Added a periodic, read-only storage health foundation covering non-waking SMART status and temperatures, Linux MD health and recovery progress, imported ZFS pool status when tooling is available, and hardware RAID controller discovery. Hardware member/cache/battery health is reported as limited until a supported vendor adapter exists, and fixture tests cover healthy and degraded arrays, a failing disk, ZFS degradation, and symbolic-link output rejection.
- Added atomic storage alert and audit state for SMART failure, high temperature, degraded MD/ZFS storage, and limited hardware RAID visibility. Repeated scans are deduplicated, first-seen time is retained, severity changes and resolutions are recorded, history is bounded to 1,000 events, and invalid or indirect state is rejected.
- Added fail-closed, review-only creation plans for ZFS mirror/RAID-Z1/RAID-Z2 and Linux MD RAID 1/5/6/10. Planning enforces unique eligible disks, exact destructive confirmation, minimum disk counts, matching sector sizes, bounded numeric capacity, usable-capacity and resilience explanations, hardware/software RAID stacking rules, and advanced limited-visibility acknowledgement without emitting a command or authorization token.
- Added the complete guided local-console first-run flow for hostname, administrator, DHCP or static IPv4 networking, time zone, automatic clock synchronization, and the signed-update check preference. Configuration is strictly validated, plaintext passwords are never written, applied state is secret-free, and a failed network activation rolls back the newly created user and all changed settings.
- Enabled first-run setup automatically on the first local boot, added the required dialog package, and added focused tests for accepted DHCP/static configurations, unsafe input rejection, one-time completion, permissions, secret redaction, and transactional rollback.
- Marked the v0.3 first-run wizard and automated interrupted-write/bad-media/recovery test requirements complete. The remaining v0.3 release gates are approved physical USB write/verify/boot evidence and a terminal-free real-system installation/boot/persistent-reboot acceptance run.
- Added a terminal-free guided on-server installer that automatically opens on tty1 only when booted from packaged live media, filters to eligible internal targets, requires the exact model/path/capacity erase phrase, performs a second destructive review, and consumes the existing short-lived protected request and writer chain.
- Prevented the installed-system first-run wizard from opening on live installation media, added verified completion/recovery screens and reboot/power-off choices, and added non-destructive guided-flow tests for success, wrong confirmation, no eligible disk, and live-versus-installed console isolation.
- Added a strict privacy-safe physical system-install report and fixture-only test mode covering the acceptance writer, fresh selection, terminal-free flow, exact confirmation, write/reread/GPT/state verification, healthy installed boot, hardware inventory, first-run completion, and persistence across reboot.
- Added pinned, native preview packaging for Linux `.deb`, Windows NSIS, and macOS `.dmg` artifacts. Preview packages include an explicit non-release notice, have no production trust anchor, keep physical writing disabled, and are retained only long enough for packaging review.
- Passed native preview packaging for Windows, Linux, and macOS together in Installer desktop run `32795296293`; corrected Windows release packaging to use the runner's native Perl instead of Git Bash's incomplete Perl, and strengthened the packaging contract to prevent regression.
- Marked the v0.3 cross-platform installer-build requirement complete. v0.3 now has six of eight requirements complete; approved physical USB/DVD evidence and a real disposable-system-disk installation/boot remain open.
- Strengthened the final v0.2 boot evidence contract with strict schema-2 physical-versus-fixture modes, exact VMware/Hyper-V Generation 2/physical platform rules, verified same-image SHA-256, UEFI and Secure Boot state, complete inventory and persistent-reboot checks, and rejection of private or unknown fields.
- Hardened removable-media evidence to reject write-only or unbooted media, indirect or oversized reports, unknown/private fields, malformed timestamps, oversized values, and Linux partition paths presented as whole disks. The writer now emits an intentionally incomplete report until a real UEFI boot and guided-installer observation are recorded. Added one final 0.2/0.3 acceptance command that requires six distinct physical reports for VMware, Hyper-V Generation 2, physical Intel, physical AMD, disposable USB, and installed-system acceptance, all bound to one exact image SHA-256.

### Next starting point

- Hardware acceptance was intentionally deferred on 2026-08-26 for a later desktop session. Keep v0.2 at seven of eight and v0.3 at six of eight until the six reports in `docs/ACCEPTANCE-0.2-0.3.md` pass together for one exact signed image SHA-256.
- No physical disk was authorized by the deferral. Explicitly identify and approve each disposable USB or internal target at the time of testing before any write begins.
- Boot-test the v0.2 image on physical Intel and AMD systems and the remaining common VM platforms.
- Use `bedrock-boot-acceptance prepare` and `complete` during each of those sessions so the report is generated from two observed healthy boots rather than hand-authored JSON.
- Build the updated image and perform the local-console first-run acceptance run, including one forced network failure followed by a successful retry.
- Run the guarded writer on an explicitly approved disposable USB drive, boot it, and archive privacy-safe evidence; then repeat the protected on-server install on an approved disposable system disk.
- Require the new disposable Linux storage acceptance job to pass, then archive model-specific physical hardware RAID evidence as supported controllers are qualified.
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
- Extended signed manifests with the exact expanded size and SHA-256 of bytes destined for disk.
- Added streaming Zstandard raw-image writing with expanded-byte capacity checks and full post-write verification.
- Added deterministic interrupted-write failure handling that requires a complete rewrite, plus compressed-raw and interruption regression coverage.
- Added the branded responsive graphical installer shell with guided verification, removable-drive selection, exact erase confirmation, write progress, recovery messages, and keyboard-accessible explanations.
- Restricted the UI to three narrow desktop-bridge commands so frontend code cannot enumerate or write disks directly.

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
