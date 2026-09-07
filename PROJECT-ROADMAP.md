# Bedrock Server OS project roadmap

Bedrock Server OS has completed **0.1.0 — Product definition** and the independently testable **0.4.0 — Storage and NAS** milestone. The 0.2 bootable foundation and 0.3 installer are implemented through their safe automated gates, with named physical and cross-hypervisor acceptance work still required before either earlier milestone can be declared complete. Version 1.0 means a fully functional, tested, documented, signed, and supportable product that is ready to ship.

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
- [ ] Implement dashboard telemetry, tasks, progress, alerts, and audit history.
  - Authenticated privacy-safe dashboard, task/progress, active-alert, and bounded audit read contracts are implemented with independent failure behavior. A serialized task/audit producer rejects regressions and unsafe state; verified update downloads, VM power actions, and guarded storage operations publish real progress and terminal audit outcomes. Remaining operations and UI integration must be wired before this item can close.
- [ ] Finish Storage, VMs, Images, Apps, Connect, Backup, Hardware, Settings, and Help.
- [ ] Add advanced disclosures without hiding health or safety information.
- [ ] Add keyboard-complete controls and WCAG 2.2 AA testing.
- [ ] Handle offline, reconnecting, partial failure, and concurrent changes.
- [ ] Add API schema tests, authorization tests, and UI end-to-end tests.
  - The authenticated OpenAPI 3.1 document covers every implemented v1 route and its bearer security policy. Route/schema agreement and token issue/revocation tests pass; complete response-schema and UI end-to-end coverage remain.

Exit: every supported server task works through the UI and documented API.

## 0.7.0 — Remote access and desktop clients

- [x] Design end-to-end encrypted remote transport and threat model.
  - Noise XX mutual device authentication, relay TLS, transcript binding, record/rekey limits, revocation, privacy, adversaries, limitations, and implementation/review gates are fixed in a machine-validated policy and [threat model](docs/REMOTE-ACCESS-THREAT-MODEL.md). Implementation remains in the following items.
- [ ] Implement one-time QR/manual-code pairing with server approval and expiry.
  - A root-only backend issues QR/manual payloads, stores only code and client-key hashes, requires exact local approval, expires after ten monotonic minutes or reboot, caps attempts, and atomically rejects replay. Interface and relay ingress integration remain.
- [ ] Issue per-device keys; support listing, renaming, expiry, and revocation.
  - Pairing redemption atomically registers the client's distinct public key. A root-only manager provides bounded renaming/expiry and exact-confirmation revocation; a hardened collector publishes a key-free device view through the authenticated API. Interface integration and active-session termination remain.
- [ ] Add optional Google OpenID Connect without exposing server data to Google.
- [ ] Build signed Windows and universal macOS desktop clients.
- [ ] Add automatic client updates, certificate pinning, and secure local key storage.
- [ ] Implement relay/fallback behavior without opening unsafe inbound ports.
- [ ] Complete third-party security review of pairing, auth, transport, and update paths.

Exit: approved clients connect remotely, survive network changes, and can be immediately revoked.

## 0.8.0 — Backup, recovery, apps, and operations

- [ ] Implement local and remote backup plans, schedules, retention, encryption, and restore.
- [x] Add configuration export/import and bare-metal recovery documentation.
  - Exact-confirmation export/import uses a bounded allowlist, version and SHA-256 binding, link/traversal rejection, staged replacement, local rollback copies, and an explicit reboot gate while excluding credentials and bulk data. See [bare-metal recovery](docs/BARE-METAL-RECOVERY.md).
- [ ] Build an isolated application/service system with resource limits and update policy.
- [ ] Add notification destinations and actionable health alerts.
- [x] Implement diagnostic bundles with secret redaction and explicit user consent.
  - A root-only, exact-consent tool creates owner-readable archives from bounded allowlisted system state, records unavailable sources, redacts identifying and secret-bearing keys and values, refuses overwrite, and excludes logs, user data, credentials, pairing state, and command arguments. See [diagnostic bundle policy](docs/DIAGNOSTICS.md).
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
