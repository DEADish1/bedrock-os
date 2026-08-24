# Bedrock Server OS project roadmap

Bedrock Server OS has completed **0.1.0 — Product definition** and is beginning the **0.2.0 bootable foundation**. Version 1.0 means a fully functional, tested, documented, signed, and supportable product that is ready to ship.

## Release rules

- A milestone is complete only when every required checkbox is complete and its acceptance tests pass.
- Security, data-integrity, installer, and recovery failures block a release.
- Every release updates `CHANGELOG.md`, the website status page, version metadata, and downloadable checksums.
- Preview-only UI must never be presented as working infrastructure.

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
- [x] Add read-only system partition and persistent configuration/data partitions.
- [x] Detect CPU, RAM, disks, NICs, and supported GPUs.
- [x] Build a signed update manifest and rollback-capable updater.
- [x] Produce first bootable ISO and raw USB image with SHA-256 checksums.
- [ ] Boot-test on physical Intel/AMD systems and common VM platforms.

Exit: a repeatable image boots, identifies hardware, persists configuration, updates, and rolls back.

## 0.3.0 — Installer and first-run setup

- [ ] Build Bedrock Installer for Windows, macOS, and Linux.
- [x] Safely enumerate removable drives with model, path, and capacity.
- [x] Verify downloaded image signatures and checksums before writing.
- [x] Require destructive confirmation naming the exact target drive.
- [ ] Write and verify USB media; provide ISO download and DVD guidance.
- [ ] Implement on-server installation to a selected system drive.
- [ ] Add first-run wizard for hostname, administrator, network, time, and updates.
  - Update preference step implemented: users choose automatic signed-metadata checks or manual-only checks; the rest of the first-run wizard remains open.
- [ ] Test interrupted writes, bad media, insufficient space, and recovery messages.

Exit: a new user can create media and install Bedrock without using a terminal.

## 0.4.0 — Storage and NAS

- [ ] Implement disk inventory, SMART/health, temperatures, and alerts.
  - Read-only disk, SMART health/temperature, software RAID, ZFS, and controller discovery plus deduplicated alert/audit state implemented; UI and notification delivery remain open.
- [ ] Create, expand, scrub, export, and import storage pools.
- [ ] Support OpenZFS mirrors/RAID-Z and Linux software RAID (`mdadm`) with single-/dual-drive failure protection where valid.
- [ ] Detect supported hardware RAID controllers and logical volumes; surface controller, cache/battery, disk, and rebuild health when vendor tooling permits.
  - Controller discovery and limited-health reporting implemented; vendor member/cache/battery adapters remain open.
- [ ] Add guided RAID creation, degraded-array, replacement, rebuild-progress, scrub/check, and safe import workflows.
- [ ] Implement datasets/shares, quotas, snapshots, recycle behavior, and permissions.
- [ ] Add SMB; evaluate NFS and optional Time Machine support.
- [ ] Add users, groups, access-control lists, and credential rotation.
- [ ] Implement degraded-pool, drive-replacement, and recovery workflows.
- [ ] Test power-loss behavior, disk failure, pool import, and data-integrity checks.

Exit: NAS and software/hardware RAID workflows are safe, monitored, recoverable, and usable from Windows/macOS/Linux.

## 0.5.0 — Virtual machines and image library

- [ ] Integrate KVM/QEMU and libvirt or an approved equivalent.
- [ ] Create/start/stop/restart/delete/clone/snapshot VMs.
- [ ] Assign vCPUs, RAM, storage, firmware, network, and boot order.
- [ ] Implement GPU and USB passthrough with IOMMU validation and safety guidance.
- [ ] Upload/import ISO, IMG, QCOW2, VHDX, VMDK, and supported archives.
- [ ] Validate images, track provenance/checksums, and convert formats safely.
- [ ] Provide browser console and remote-display access.
- [ ] Document Windows drivers and macOS-on-Apple-hardware license/compatibility limits.

Exit: supported Linux and Windows guests install, run, persist, snapshot, restore, and use assigned resources.

## 0.6.0 — Management interface and API

- [ ] Replace prototype data with a versioned authenticated API.
- [ ] Implement dashboard telemetry, tasks, progress, alerts, and audit history.
- [ ] Finish Storage, VMs, Images, Apps, Connect, Backup, Hardware, Settings, and Help.
- [ ] Add advanced disclosures without hiding health or safety information.
- [ ] Add keyboard-complete controls and WCAG 2.2 AA testing.
- [ ] Handle offline, reconnecting, partial failure, and concurrent changes.
- [ ] Add API schema tests, authorization tests, and UI end-to-end tests.

Exit: every supported server task works through the UI and documented API.

## 0.7.0 — Remote access and desktop clients

- [ ] Design end-to-end encrypted remote transport and threat model.
- [ ] Implement one-time QR/manual-code pairing with server approval and expiry.
- [ ] Issue per-device keys; support listing, renaming, expiry, and revocation.
- [ ] Add optional Google OpenID Connect without exposing server data to Google.
- [ ] Build signed Windows and universal macOS desktop clients.
- [ ] Add automatic client updates, certificate pinning, and secure local key storage.
- [ ] Implement relay/fallback behavior without opening unsafe inbound ports.
- [ ] Complete third-party security review of pairing, auth, transport, and update paths.

Exit: approved clients connect remotely, survive network changes, and can be immediately revoked.

## 0.8.0 — Backup, recovery, apps, and operations

- [ ] Implement local and remote backup plans, schedules, retention, encryption, and restore.
- [ ] Add configuration export/import and bare-metal recovery documentation.
- [ ] Build an isolated application/service system with resource limits and update policy.
- [ ] Add notification destinations and actionable health alerts.
- [ ] Implement diagnostic bundles with secret redaction and explicit user consent.
- [ ] Add UPS shutdown integration and safe maintenance mode.
- [ ] Run full restore drills for files, VM data, configuration, and failed system drives.

Exit: users can prove that data and configuration can be restored after realistic failures.

## 0.9.0 — Release candidate

- [ ] Freeze 1.0 scope, APIs, migrations, and supported hardware matrix.
- [ ] Run upgrade tests from every supported pre-1.0 release.
- [ ] Run soak, load, power-loss, disk-failure, network-loss, and recovery tests.
- [ ] Complete penetration test, dependency review, SBOM, and vulnerability process.
- [ ] Sign/notarize OS images, installers, clients, manifests, and releases.
- [ ] Finish installation, admin, troubleshooting, recovery, privacy, and security docs.
- [ ] Finalize license notices, macOS guidance, telemetry policy, support, and issue templates.
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
