# Bedrock Server OS project roadmap

Bedrock Server OS has completed **0.1.0 — Product definition** and the independently testable **0.4.0 — Storage and NAS** milestone. The 0.2 bootable foundation and 0.3 installer are implemented through their safe automated gates, with named physical and cross-hypervisor acceptance work still required before either earlier milestone can be declared complete. Version 1.0 means a fully functional, tested, documented, signed, and supportable product that is ready to ship.

## Release rules

- A milestone is complete only when every required checkbox is complete and its acceptance tests pass.
- Security, data-integrity, installer, and recovery failures block a release.
- Every release updates `CHANGELOG.md`, the website status page, version metadata, and downloadable checksums.
- Preview-only UI must never be presented as working infrastructure.

## Current remaining-work index

This index is the short, actively maintained view of the open path to 1.0. The milestone sections below remain the authoritative detailed requirements; completing an item here does not close a milestone checkbox until its stated acceptance evidence also passes.

- [x] Restore the current branch to green CI by resolving the storage-expansion authenticated API test failure. [Run 34765144873](https://github.com/DEADish1/bedrock-os/actions/runs/34765144873) passed validation, both clean image builds, attestation, and byte-for-byte reproducibility.
- [ ] Complete physical boot and installer acceptance on supported Intel and AMD systems, including verified USB writing and a successful disposable-system-disk install. **Requires physical hardware.**
- [ ] Complete cross-hypervisor boot acceptance and distinct Linux and Windows guest sessions on the exact release-candidate image. **Requires acceptance hosts and Windows installation media/license.**
- [ ] Finish all remaining authenticated management mutations, VM console integration, advanced disclosures, concurrent-change protection, keyboard/WCAG 2.2 AA verification, and browser end-to-end tests.
- [ ] Complete remote pairing redemption, transport/session binding, optional Google OpenID Connect, relay/fallback operation, and automatic client updates.
- [ ] Build and acceptance-test the production Windows and universal macOS desktop clients, including certificate pinning and secure local key storage. **Requires Windows and Apple test/signing environments.**
- [ ] Complete the independent security review of pairing, authentication, transport, updates, dependencies, SBOM, vulnerability handling, and penetration testing. **Requires an independent reviewer.**
- [ ] Complete controlled UPS discharge/recovery acceptance and the full file, VM, configuration, and replacement-system-drive restore drill. **Requires physical hardware.**
- [ ] Run every supported pre-1.0 upgrade path plus release-candidate soak, load, abrupt-power-loss, disk-failure, network-loss, and recovery tests. **Requires release-candidate hardware and time.**
- [ ] Sign and notarize OS images, installers, clients, manifests, and release artifacts. **Requires production signing authority and credentials.**
- [ ] Recruit the beta group, triage all ship-blocking findings, and publish release-candidate checksums. **Requires beta participants.**
- [ ] Publish the signed 1.0 ISO, raw USB image, installers, desktop clients, checksums, source/tag, website, final documentation, support/monitoring readiness, and acceptance record; issue final go/no-go approval.

## 0.1.0 — Product definition (complete)

- [x] Define Bedrock name, identity, tone, colors, and supplied assets.
- [x] Prototype dashboard, storage, VM, image-library, installer, and remote-access experiences.
- [x] Add contextual `(?)` help and resource-selection controls.
- [x] Add Windows/macOS client concepts, QR pairing, trusted devices, and Google sign-in concept.
- [x] Publish a private interactive product prototype.
- [x] Establish versioned roadmap and update log.
- [x] Decide supported hardware baseline and CPU architectures.
- [x] Record final technical architecture decisions.

Exit: product scope, supported hardware, architecture, and release process are approved.

## 0.2.0 — Bootable foundation (current)

- [x] Select the Linux base distribution and define the kernel pinning policy.
- [x] Create reproducible OS image builds in CI.
- [x] Implement UEFI boot, boot splash, service startup, and diagnostics mode.
  - The USB/ISO boot menu now includes a non-destructive live hardware test that keeps its report in RAM, suppresses the guided installer, and checks the 1.0 UEFI, x86-64, CPU-thread, memory, virtualization, disk-capacity, and wired-network baseline without selecting or writing a disk.
- [x] Add read-only system partition and persistent configuration/data partitions.
- [x] Detect CPU, RAM, disks, NICs, and supported GPUs.
- [x] Build a signed update manifest and rollback-capable updater.
- [x] Produce first bootable ISO and raw USB image with SHA-256 checksums.
- [ ] Boot-test on physical Intel/AMD systems and common VM platforms.

Exit: a repeatable image boots, identifies hardware, persists configuration, updates, and rolls back.

## 0.3.0 — Installer and first-run setup

- [x] Build Bedrock Installer for Windows, macOS, and Linux.
  - Native unsigned, non-writing preview packages (`.exe`, `.deb`, and `.dmg`) passed together in [Installer desktop run #61](https://github.com/DEADish1/bedrock-os/actions/runs/32795296293). Production signing/trust and approved physical-media writing remain separate release gates.
- [x] Safely enumerate removable drives with model, path, and capacity.
- [x] Verify downloaded image signatures and checksums before writing.
- [x] Require destructive confirmation naming the exact target drive.
- [ ] Write and verify USB media; provide ISO download and DVD guidance.
- [ ] Implement on-server installation to a selected system drive.
  - Protected write, reread, GPT finalization, state growth, and a terminal-free local-console workflow are implemented and pass disposable-image tests. The checkbox remains open until an approved disposable physical system disk installs and boots successfully.
- [x] Add first-run wizard for hostname, administrator, network, time, and updates.
  - The local-console wizard validates every value, stores only a password hash, applies settings transactionally, rolls back failed network activation, and records a secret-free completion marker. Real-image console acceptance remains part of the 0.3 exit test.
- [x] Test interrupted writes, bad media, insufficient space, and recovery messages.
  - Automated virtual-device and interface tests cover interruption, insufficient capacity, checksum mismatch, unavailable media, approval failure, malformed progress, safe retry, and final trust state. Physical-media acceptance remains open under the write-and-verify item above.

Exit: a new user can create media and install Bedrock without using a terminal.

## 0.4.0 — Storage and NAS (complete)

- [x] Implement disk inventory, SMART/health, temperatures, and alerts.
  - Read-only direct-disk, SMART health/temperature, Linux RAID, ZFS, controller, StorCLI, deduplicated alert, and bounded audit state pass fixture and schema tests.
- [x] Create, expand, scrub, export, and import storage pools.
  - The guarded executor refreshes whole-device safety, requires exact confirmation, serializes changes, and commits managed state only after successful OpenZFS or Linux RAID operations.
- [x] Support OpenZFS mirrors/RAID-Z and Linux software RAID (`mdadm`) with single-/dual-drive failure protection where valid.
  - ZFS mirror/RAID-Z1/RAID-Z2 and Linux RAID 1/5/6/10 validation is enforced; ZFS expansion adds only a complete protected vdev and unsafe RAID 10 member-count reshape remains blocked.
- [x] Detect supported hardware RAID controllers and logical volumes; surface controller, cache/battery, disk, and rebuild health when vendor tooling permits.
  - StorCLI controller, member, logical-volume, cache-protection, and rebuild telemetry is normalized and alerted; controllers without a supported tool remain explicitly limited rather than inferred healthy.
- [x] Add guided RAID creation, degraded-array, replacement, rebuild-progress, scrub/check, and safe import workflows.
  - A terminal-free local-console flow explains layouts, selects disks, requires the full pool/layout/device phrase, shows a final review, and delegates to independently repeated privileged checks.
- [x] Implement datasets/shares, quotas, snapshots, recycle behavior, and permissions.
  - OpenZFS datasets, byte quotas, manual snapshots, ACLs, and per-user Samba recycle behavior are stateful and covered by secret-redaction tests.
- [x] Add SMB; evaluate NFS and optional Time Machine support.
  - SMB is primary with SMB2.1 minimum and no guest mapping; NFS is explicit opt-in; Time Machine uses writable SMB and requires a dataset quota.
- [x] Add users, groups, access-control lists, and credential rotation.
  - Password rotation uses a bounded root-readable file and never records plaintext in requests, arguments, state, or audits.
- [x] Implement degraded-pool, drive-replacement, and recovery workflows.
  - Managed storage exposes degraded/rebuilding states, protected replacement, scrub/check, export/import, boot reactivation, and recovery guidance.
- [x] Test power-loss behavior, disk failure, pool import, and data-integrity checks.
  - Transaction interruption is injected before durable state commit; the dedicated Linux job exercises real disposable ZFS/Linux RAID failure, replacement, export/import or reassembly, scrub/check, and post-recovery SHA-256 integrity.

Exit: passed in [Storage and NAS acceptance run #1](https://github.com/DEADish1/bedrock-os/actions/runs/33016715779). Physical abrupt-power soak remains a 0.9 release-candidate gate; controller qualification remains model-specific and cannot upgrade limited telemetry without real vendor evidence.

## 0.5.0 — Virtual machines and image library

- [x] Integrate KVM/QEMU and libvirt or an approved equivalent.
  - KVM acceleration, packaged QEMU/OVMF, and the system libvirt connection fail closed through the boot capability report.
- [x] Create/start/stop/restart/delete/clone/snapshot VMs.
  - Guarded lifecycle helpers serialize changes, require exact confirmation, verify final state, and roll back partial mutations; deletion is recoverable from quarantine.
- [x] Assign vCPUs, RAM, storage, firmware, network, and boot order.
  - Resource reservations, persistent attachments, isolated networks, Q35/UEFI firmware, TPM 2.0, and bounded boot-order changes pass fixture validation.
- [x] Implement GPU and USB passthrough with IOMMU validation and safety guidance.
  - Review and mutation boundaries revalidate complete IOMMU groups or USB topology and reject boot-display, input, storage, hub, unauthorized, and host-critical devices.
- [x] Upload/import ISO, IMG, QCOW2, VHDX, VMDK, and supported archives.
  - Direct and single-member ZIP imports are bounded, path-safe, content-detected, and installed only after source and copied-byte verification.
- [x] Validate images, track provenance/checksums, and convert formats safely.
  - Imports and conversions reject encryption, backing chains, changed bytes, duplicates, and unsafe paths while recording a root-only provenance ledger.
- [x] Provide browser console and remote-display access.
  - One-time 60-second sessions redeem into a loopback-only, short-lived WebSocket proxy; VNC never listens on TCP.
- [x] Document Windows drivers and macOS-on-Apple-hardware license/compatibility limits.

Exit pending physical acceptance: one exact Bedrock image must still pass distinct Linux and Windows guest sessions proving installation, acceleration, assigned resources, console and agent readiness, reboot persistence, and snapshot restoration.

## 0.6.0 — Management interface and API

- [ ] Replace prototype data with a versioned authenticated API.
  - The overview and every named management area now use live authenticated read routes, keep the bearer token in memory only, and render explicit unavailable/partial states. A separately hardened, kernel-peer-authenticated root action broker now powers a strict idempotent update-policy mutation route; the remaining authenticated mutations must be implemented before this item can close.
- [ ] Implement dashboard telemetry, tasks, progress, alerts, and audit history.
  - Authenticated privacy-safe dashboard, task/progress, active-alert, and bounded audit read contracts are implemented with independent failure behavior and now render in a live Activity interface with explicit empty, partial, disconnected, and unavailable states. A serialized task/audit producer rejects regressions and unsafe state; verified update downloads, VM power actions, and guarded storage operations publish real progress and terminal audit outcomes. Remaining operations must be wired before this item can close.
- [ ] Finish Storage, VMs, Images, Apps, Connect, Backup, Hardware, Settings, and Help.
  - Apps and Backup publish bounded privacy-safe state through authenticated, schema-defined v1 routes, and both interface areas render authenticated live, empty, and independently unavailable states. Applications expose verified running/update state plus guarded, idempotent root-staged installation, start/stop, rollback-capable server-side candidate updates, and data-preserving removal; backup plans support root-staged privacy-safe creation, guarded “run now,” and latest-snapshot restore controls. Every mutation requires exact confirmation and server-confirmed refresh. Registry/digest, container internals, filesystem/repository, credential, initialization, and snapshot identifiers remain outside the API service boundary. Apps and Backup interface software functionality is complete; cross-area physical acceptance remains.
  - Hardware now has a dedicated authenticated v1 read contract and live interface view for processor, memory, disk capacity, virtualization, graphics, controller, network, and USB summaries while stripping device paths, interface and bus identities, MAC addresses, serials, and passthrough topology. Hardware mutations and the other management areas remain.
  - Virtual machines now have a dedicated authenticated v1 inventory and live controls for creation, power, offline snapshots, cloning, recoverable deletion, offline CPU/memory/boot updates, managed image/network attachments, and GPU/USB passthrough. A purpose-specific feed exposes only safe passthrough candidates and active assignments; the offline editor requires two-stage confirmation, and execution revalidates hardware while preventing cross-VM reuse. Host paths, console sockets, MAC addresses, raw definitions, and passthrough topology remain outside general inventory responses; console integration remains.
  - The image library publishes a root-generated path-free inventory after initialization, import, and conversion, with an authenticated v1 contract and live interface for format, size, SHA-256, conversion provenance, browser-to-staging uploads, guarded format validation/import, hash-bound staged-upload discard, and hash-bound conversion to QCOW2 or raw images. Uploads are streamed into a confined unprivileged directory, hashed server-side, reviewed by exact hash confirmation, revalidated at the root boundary, and removed after import or explicit discard; import and discard are mutually locked.
  - Storage now has a dedicated authenticated v1 read contract and live interface for capacity, SMART health, software RAID/ZFS state and rebuild progress, bounded hardware-RAID visibility, protected creation and expansion, guarded member replacement and integrity scrubs, and managed export/import. A root-only keyed identity map lets the interface select disks and members without exposing device paths or serials; every destructive operation refreshes eligibility and resolves paths, backend, layout, and membership only at the root boundary. Exported groups remain visible so they can be reconnected. Physical-disk execution remains part of cross-area acceptance.
  - Remote Access now renders the authenticated privacy-safe trusted-device feed with active, expired, revoked, empty, disconnected, and unavailable states. Live rename, expiry, and revocation controls use authenticated idempotent mutations through a strict root wrapper; revocation terminates active sessions and every change publishes task/audit state. Pairing controls and signed desktop clients remain.
  - Settings now has a dedicated authenticated read contract and live interface for the validated update-check choice, stable/beta channel, enforced manual installation, and telemetry-disabled state. Hostname, account, network, credential, and other first-run configuration remain outside the response; authenticated mutations remain.
  - Help now links directly to the version-controlled installation, first-run, administration, troubleshooting, diagnostic/privacy, and support guidance. Contextual safety help remains embedded throughout management views.
  - Users now has a dedicated authenticated contract and live interface for managed NAS accounts, credential-rotation state, group membership counts, exact-confirmation creation of fixed-policy local users and groups, membership additions, and root-staged credential rotation. Passwords, hashes, member identities, numeric IDs, shell/home options, datasets, ACLs, share paths, and snapshots remain outside the API and browser boundary.
- [x] Add advanced disclosures without hiding health or safety information.
  - Keyboard-operable native disclosures expose privacy-safe processor topology, link capabilities, controllers, physical-media characteristics, SMART history, protected-storage topology, candidate eligibility, and software-storage capabilities. Primary health, rebuild state, compatibility, and destructive warnings remain visible when every disclosure is closed; browser acceptance verifies that invariant and automated WCAG A/AA behavior.
- [ ] Add keyboard-complete controls and WCAG 2.2 AA testing.
  - Automated Chromium acceptance now reaches every management area by keyboard and reports no axe WCAG A/AA violations, including WCAG 2.2 AA rules. Manual assistive-technology, zoom/reflow, and physical-device verification remain before this item can close.
- [ ] Handle offline, reconnecting, partial failure, and concurrent changes.
  - Independent dashboard components already degrade without collapsing the full response. API state and audit reads pin non-symlink file descriptors and reject mid-read mutation. The interface now detects browser-offline and transient API failures, retains visibly labeled last-confirmed state, pauses management controls, retries on network return and while visible, and clears credentials on an explicit authorization failure. Settings mutations now require the exact strong ETag loaded with the displayed policy and reject stale changes for review. The same explicit stale-state contract still must extend across every other mutation family before this item can close.
- [ ] Add API schema tests, authorization tests, and UI end-to-end tests.
  - The authenticated OpenAPI 3.1 document covers every implemented v1 route and its bearer security policy. Route/schema agreement, recursive successful-response conformance, every documented operation with missing and invalid bearer credentials, and token issue/revocation tests pass. Initial browser end-to-end coverage now verifies token entry, all management-area navigation, an authenticated idempotent settings mutation, server-confirmed refresh, and automated accessibility checks. Remaining mutation flows and console integration still need browser coverage.

Exit: every supported server task works through the UI and documented API.

## 0.7.0 — Remote access and desktop clients

- [x] Design end-to-end encrypted remote transport and threat model.
  - Noise XX mutual device authentication, relay TLS, transcript binding, record/rekey limits, revocation, privacy, adversaries, limitations, and implementation/review gates are fixed in a machine-validated policy and [threat model](docs/REMOTE-ACCESS-THREAT-MODEL.md). Implementation remains in the following items.
- [ ] Implement one-time QR/manual-code pairing with server approval and expiry.
  - A root-only backend issues QR/manual payloads, stores only code and client-key hashes, requires exact local approval, expires after ten monotonic minutes or reboot, caps attempts, and atomically rejects replay. The authenticated interface lists sanitized pending requests and performs guarded idempotent approval without exposing codes or keys. A dedicated rate-limited Unix-socket gateway now gives only the isolated remote-transport identity bounded request, redemption, and exact paired-key session authorization with indistinguishable errors and secret-free process arguments; an idempotent service provisions and verifies the server X25519 identity first. Relay ingress and reviewed Noise client transport integration remain.
- [ ] Issue per-device keys; support listing, renaming, expiry, and revocation.
  - Pairing redemption atomically registers the client's distinct public key. A root-only manager and authenticated interface provide bounded listing, renaming, expiry, and exact-confirmation revocation; a hardened collector publishes a key-free device view through the authenticated API. Session authorization matches the registered public key, rejects expired/revoked devices, records last-seen time, and starts the device's dedicated target; revocation persists before synchronously stopping that target. Concrete Noise transport-service membership remains.
- [ ] Add optional Google OpenID Connect without exposing server data to Google.
- [ ] Build signed Windows and universal macOS desktop clients.
- [ ] Add automatic client updates, certificate pinning, and secure local key storage.
- [ ] Implement relay/fallback behavior without opening unsafe inbound ports.
- [ ] Complete third-party security review of pairing, auth, transport, and update paths.

Exit: approved clients connect remotely, survive network changes, and can be immediately revoked.

## 0.8.0 — Backup, recovery, apps, and operations

- [x] Implement local and remote backup plans, schedules, retention, encryption, and restore.
  - Root-only restic plans support confined local and bounded SFTP repositories, external owner-only passwords, daily/weekly UTC scheduling, daily/weekly/monthly retention, verified snapshot history, and exact-confirmation restores into new destinations. See [encrypted backups](docs/BACKUP.md).
- [x] Add configuration export/import and bare-metal recovery documentation.
  - Exact-confirmation export/import uses a bounded allowlist, version and SHA-256 binding, link/traversal rejection, staged replacement, local rollback copies, and an explicit reboot gate while excluding credentials and bulk data. See [bare-metal recovery](docs/BARE-METAL-RECOVERY.md).
- [x] Build an isolated application/service system with resource limits and update policy.
  - Digest-pinned Podman workloads run non-root with read-only roots, no capabilities or privilege escalation, bounded CPU/memory/PIDs, controlled bridge exposure, one confined persistent-data mount, exact-confirmation lifecycle operations, and manual or notification-only update policy. See [isolated applications](docs/APPLICATIONS.md).
- [x] Add notification destinations and actionable health alerts.
  - Root-only HTTPS webhook and TLS email destinations use separate owner-only credentials, SHA-256-bound configuration, privacy-safe event payloads, specific recovery actions, per-destination deduplication, and scheduled retry of failed deliveries. See [health notifications](docs/NOTIFICATIONS.md).
- [x] Implement diagnostic bundles with secret redaction and explicit user consent.
  - A root-only, exact-consent tool creates owner-readable archives from bounded allowlisted system state, records unavailable sources, redacts identifying and secret-bearing keys and values, refuses overwrite, and excludes logs, user data, credentials, pairing state, and command arguments. See [diagnostic bundle policy](docs/DIAGNOSTICS.md).
- [ ] Add UPS shutdown integration and safe maintenance mode.
  - A guarded maintenance backend now blocks packaged mutation entry points, rejects unmanaged running guests, gracefully stops managed guests, quiesces active shares and timers, syncs filesystems, and restores only previously active units. NUT low-battery/FSD handling records state and requests poweroff even after a quiesce failure. A controlled physical UPS discharge/recovery acceptance run remains before this item can close.
- [ ] Run full restore drills for files, VM data, configuration, and failed system drives.
  - A strict, privacy-safe acceptance report now requires matching file and VM hashes, overwrite protection, VM boot and snapshot recovery, configuration reboot and credential rotation, plus a clean replacement-system-drive install and non-destructive pool import. The physical drill and signed-off report remain required before this item can close. See [full restore drill](docs/RESTORE-DRILL.md).

Exit: users can prove that data and configuration can be restored after realistic failures.

## 0.9.0 — Release candidate

- [x] Freeze 1.0 scope, APIs, migrations, and supported hardware matrix.
  - A machine-validated [1.0 scope freeze](docs/1.0-SCOPE-FREEZE.md) fixes the supported product boundary, additive v1 API contract, 0.2 upgrade floor and atomic migration guarantees, minimum amd64/UEFI hardware baseline, deferred features, and acceptance-dependent hardware qualifications without treating unfinished work as complete.
- [ ] Run upgrade tests from every supported pre-1.0 release.
- [ ] Run soak, load, power-loss, disk-failure, network-loss, and recovery tests.
- [ ] Complete penetration test, dependency review, SBOM, and vulnerability process.
  - Every OS image build now emits a deterministic SPDX 2.3 JSON SBOM from the exact resolved Debian package set, verifies its structure and manifest-bound SHA-256/package count, and requires matching SBOM evidence across reproducibility replicas. The web dependency audit is currently clean. Standalone CI artifact publication, independent dependency review, vulnerability-response acceptance, and penetration testing remain.
- [ ] Sign/notarize OS images, installers, clients, manifests, and releases.
- [x] Finish installation, admin, troubleshooting, recovery, privacy, and security docs.
  - A validated documentation index now connects installation and first-run procedures, routine administration, subsystem operations, troubleshooting, bare-metal and drill recovery, privacy/telemetry policy, security architecture, support, and milestone acceptance evidence.
- [x] Finalize license notices, macOS guidance, telemetry policy, support, and issue templates.
  - The repository now carries a project-wide MIT license, third-party notice and release-obligation policy, off-by-default privacy/telemetry contract, supported macOS installer and unsupported macOS-host/guest boundaries, privacy-safe support guidance, private security-report routing, and structured public issue forms.
- [ ] Recruit beta group, triage blockers, and publish release-candidate checksums.

Exit: no open ship-blocking defects; release candidate passes security, recovery, upgrade, and usability gates.

## 1.0.0 — Ready to ship

- [ ] Publish signed Bedrock OS ISO and USB image with verified checksums.
- [ ] Publish signed Bedrock Installer for Windows, macOS, and Linux.
- [ ] Publish signed Bedrock Client for Windows and macOS.
- [ ] Publish source repositories, tagged release, SBOM, licenses, and reproducible-build instructions.
- [ ] Launch download website, documentation, status page, release notes, and support channels.
- [ ] Confirm update and rollback services are operational and monitored.
- [ ] Complete final clean-install, upgrade, backup, restore, pairing, and revocation acceptance run.
- [ ] Archive signed release evidence and approve general availability.

Exit: Bedrock is fully functional, tested, documented, signed, recoverable, supportable, and available for installation.
