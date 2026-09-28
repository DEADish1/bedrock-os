# Bedrock OS goal checklist through 1.0

Reviewed 2026-09-26. This is the active execution plan. Numbers below are target work versions, not shipped versions. The endpoint is **1.0.0**. Requirements remain governed by `PROJECT-ROADMAP.md` and `release/1.0-contract.json`; the previous `REMAINING-WORK.md` remains a traceability record. No original release requirement is removed.

## Review baseline

- Branch: `codex/latest-update`; reviewed committed baseline: `6b0a671`. Local task-retention changes were unfinished at review time.
- [Build 35733035907](https://github.com/DEADish1/bedrock-os/actions/runs/35733035907) passed configuration validation, both image builds, and reproducibility. The physical acceptance-kit job was skipped. This does not prove production signing or hardware acceptance.
- The management UI uses same-origin API requests, while the packaged API serves a Unix socket. Installed UI delivery and the authenticated browser gateway remain release blockers.
- Upload/discard task reporting and upload restart recovery exist. Discard crash recovery, task retention, production service permissions, and complete operation-family acceptance still need work.
- Remote transport components and installer safeguards exist, but production clients, relay acceptance, hardware campaigns, signing, independent review, and final publication remain open.
- The untracked management-UI workflow is not installed in GitHub. Resolve its workflow-scope prerequisite before relying on it for release evidence.

## Working rules

Check a box only after its acceptance evidence is recorded with source commit, commands/run links, artifact hashes where applicable, result, and unresolved limitations. Code completion alone does not close hardware or release acceptance. Commit and push completed work. Continue independent software work while external gates are unavailable. Physical disk writes require an explicitly approved disposable target; signing, public release, and general availability require their named authority.

## 0.6 - Finish the installed management product

- [x] **0.6.0 - Review and rebaseline.** Inspect source, frozen scope, prior checklist, worktree, and current CI. Publish this ordered plan and retain traceability to every prior open item. Evidence: review baseline above and mapping below.
- [x] **0.6.1 - Bounded task retention.** Active tasks survive terminal-history churn, excess active work is rejected without changing saved state, and completion at full capacity frees a slot. Evidence: commit `14d226c`, `os/tests/test-api-task-state.sh`, and [Linux validation job 108480816465](https://github.com/DEADish1/bedrock-os/actions/runs/36269572212/job/108480816465), passed 2026-09-26. Image builds are separate release evidence.
- [x] **0.6.2 - Crash-consistent tasks and staging.** Finish discard crash recovery without racing imports; verify upload metadata/data consistency, interruption, cleanup, broker outages during recovery, task/audit durability, and service restart behavior. Pass failure-injection tests and verify the actual unprivileged API/root broker boundary.
  Evidence: [Linux validation at a763fed](https://github.com/DEADish1/bedrock-os/actions/runs/36348454724/job/108702296927) passed transaction replay, simulated disk-full/interruption, staged metadata and legacy recovery, production-UID tests, and packaged-systemd startup/restart tests, including the strengthened broker-outage assertion. See `TASK-AUDIT-COVERAGE.md` for commands, earlier reproducible builds, and limitations. This closes software failure-injection/service acceptance, not exact signed-image boot (0.8.1-0.8.3) or physical power loss (0.9.2).
- [ ] **0.6.3 - Installed UI and browser gateway.** Package the UI and a same-origin HTTP(S)/WebSocket gateway on the image. Define local access, TLS/trust, authentication, origin/CSRF checks, request limits, timeouts, and startup/update behavior. Prove a clean installed server serves the UI and authenticated API without exposing privileged sockets or secrets.
  In progress: the static UI is packaged and verified inside reproducible images ([04e3ce2](https://github.com/DEADish1/bedrock-os/actions/runs/36349114364)). Loopback HTTPS gateway transport acceptance with the dedicated UID, packaged systemd units, verified TLS, real API authentication, Host/Origin checks, limits and restart identity reuse passed [validation at 1fbf457](https://github.com/DEADish1/bedrock-os/actions/runs/36371536178/job/108768766870). Image builds/reproducibility for that revision are pending. Service activation, LAN/trust lifecycle, browser verification, and clean-install acceptance remain open; see `INSTALLED-MANAGEMENT-UI.md`.
- [ ] **0.6.4 - Complete setup workflows.** Provide reviewed local-console setup for API-token issue/rotation/recovery, backup repositories/passwords, application digests, and NAS credentials. Verify first-run and subsequent management without unsupported manual staging. Any scope deferral needs explicit approval.
  In progress: guided API-token issuance/revocation, fingerprint display and loopback gateway activation exist. The completed first-run wizard handoff into real token issuance passed a private-PTY test at [19576d7](https://github.com/DEADish1/bedrock-os/actions/runs/36373324734/job/108773986442), preserving saved setup state. Fresh-install/decline/failure acceptance, token-capacity recovery, trust renewal/LAN setup and the other credential workflows remain open; see `INSTALLED-MANAGEMENT-UI.md`.
  Follow-up: completed-wizard decline and helper-execution-failure checks passed at [9ef4f7f](https://github.com/DEADish1/bedrock-os/actions/runs/36373529335/job/108774605818), superseding those two pending container checks above. Full fresh-install and physical acceptance are still required.
- [ ] **0.6.5 - Mutation and contract acceptance.** Exercise all 33 packaged mutation method/path combinations and every action variant through the real gateway: success, denial, malformed input, stale ETag, confirmation, replay/conflict, and refresh. Reconcile OpenAPI and frozen v1 compatibility.
- [ ] **0.6.6 - Task/audit acceptance across subsystems.** Verify apps, backups, storage, NAS, VM lifecycle/images/networks/snapshots/passthrough, settings, and remote trust emit bounded progress and durable terminal outcomes. Review pairing/console security events, privacy, retention, and recovery; close the coverage audit.
- [ ] **0.6.7 - Real guest console.** Verify a running guest in the installed browser UI, one-time token use, expiration, disconnect/reconnect, WebSocket authorization, and absence of tokens from URLs, logs, and persisted state.
- [ ] **0.6.8 - UI resilience and accessibility.** Test all management areas against a real server in empty, offline, stale, denied, and partial-failure states. Complete keyboard, screen-reader, focus/status announcements, and 200-400% reflow/zoom checks on supported browsers. **Gate:** assistive-technology environment.
- [ ] **0.6.9 - Repeatable management CI.** Install authorized CI configuration for UI build/lint/browser tests, add real-server integration coverage, and archive test artifacts. Make a failing required check prevent release promotion. **Gate:** workflow-writing credential scope where needed.

## 0.7 - Complete remote access and clients

- [ ] **0.7.1 - Pairing end to end.** Complete QR/manual initiation, local approval, redemption, ten-minute/reboot expiry, rate limits, replay rejection, and indistinguishable bad-code handling through actual ingress and client UI.
- [ ] **0.7.2 - Device sessions and revocation.** Verify per-device keys, rename/expiry/listing, Noise identity binding, sustained API forwarding, network reconnect, immediate active-session termination, and rejection after revocation.
- [ ] **0.7.3 - Relay and network fallback.** Provision and test production outbound TLS/Noise routing, fallback, hostile framing, route limits, outage recovery, and network changes without unsafe inbound listeners. **Gate:** relay infrastructure and credentials.
- [ ] **0.7.4 - Optional Google sign-in.** Implement scoped OpenID Connect and prove server content/device inventory/API tokens are not disclosed, or obtain an explicit 1.0 deferral. **Gate:** OAuth application credentials if included.
- [ ] **0.7.5 - Windows client.** Complete native pairing, connection, revocation, certificate pinning, protected key storage, packaging, and installation acceptance. Production signing is tracked in 0.9.5. **Gate:** Windows test host.
- [ ] **0.7.6 - Universal macOS client.** Complete the same functionality on Intel and Apple Silicon; build and test both slices and OS key storage. **Gate:** Apple test hosts; signing/notarization in 0.9.5.
- [ ] **0.7.7 - Client updates.** Verify signed metadata, pin rotation, replay/downgrade rejection, interrupted updates and rollback, and preservation of device trust on both platforms.
- [ ] **0.7.8 - Independent remote security review.** Obtain review of pairing, authentication, transport, relay, revocation, client storage and updates; resolve findings and retain the signed report. **Gate:** independent reviewer.

## 0.8 - Qualify boot, installation, storage and recovery

- [ ] **0.8.1 - Intel physical boot.** Boot exact ISO/raw candidates on supported Intel UEFI hardware; record hardware inventory, live diagnostics, persistence, service health, updates, rollback, and supported Secure Boot behavior. **Gate:** Intel machine and approved test disk.
- [ ] **0.8.2 - AMD physical boot.** Repeat the boot acceptance on supported AMD hardware with virtualization and graphics detection. **Gate:** AMD machine and approved test disk.
- [ ] **0.8.3 - Hypervisor boot matrix.** Verify each supported platform across firmware, storage, NIC, display, persistence, update and recovery modes using the same candidate hashes. **Gate:** acceptance hosts.
- [ ] **0.8.4 - USB writer and ISO/DVD instructions.** Test Windows/macOS/Linux enumeration, signed download verification, exact-target confirmation, write/reread, boot, bad media and interrupted writes. Publish tested ISO/DVD and firmware/recovery guidance. **Gate:** all three hosts and disposable media.
- [ ] **0.8.5 - Live mode and system installation.** Verify non-destructive USB live hardware testing, selection of an approved system disk, guarded installation, reboot, terminal-free first-run, persistent settings and rollback. **Gate:** disposable physical system disk.
- [ ] **0.8.6 - Linux guest acceptance.** Install and boot a Linux guest with acceleration, CPU/RAM/disk/network assignments, console, readiness, reboot persistence and snapshot restore on the candidate image.
- [ ] **0.8.7 - Windows guest acceptance.** Repeat with licensed Windows media and drivers; verify isolation, agent readiness, console and snapshot recovery. **Gate:** Windows license/media and acceptance host.
- [ ] **0.8.8 - Passthrough and storage qualification.** Prove GPU/USB assignment/removal and rejection of host-critical devices; qualify claimed RAID-controller telemetry and physical storage replacement/rebuild behavior. **Gate:** IOMMU hardware, controller models and disposable drives.
- [ ] **0.8.9 - UPS, maintenance and full restore.** Run controlled low-battery shutdown and failed-quiesce recovery with guests/shares. Restore files, VM snapshots, configuration, rotated credentials and a failed system drive; verify hashes, boot, protected pool import and signed reports. **Gate:** UPS, replacement hardware and backup media.

## 0.9 - Release candidate and release operations

- [ ] **0.9.1 - Upgrade matrix.** Enumerate supported source versions from the frozen 0.2.0 floor and test each to the candidate, including schema migrations, data preservation, interruptions and rollback.
- [ ] **0.9.2 - Reliability campaign.** Run documented soak/load, power loss, disk failure/rebuild, network loss and recovery tests. Record duration, hardware, artifact hashes and every ship-blocking defect. **Gate:** hardware and sustained test time.
- [ ] **0.9.3 - Security and supply chain.** Complete penetration testing, dependency/SBOM/license review, vulnerability intake/response exercise and critical/high finding closure. Archive exact package and artifact evidence. **Gate:** independent reviewer.
- [ ] **0.9.4 - Beta and usability.** Recruit representative testers, distribute verified candidates, collect install/upgrade/restore/remote-access findings, fix blockers and publish candidate checksums. **Gate:** beta participants.
- [ ] **0.9.5 - Production signing and notarization.** Establish production OS/update/installer/client trust, sign all artifacts and manifests, notarize Apple packages, and verify from clean hosts. Verify provenance/reproducibility against the exact source. **Gate:** production keys, Windows signing and Apple authority.
- [ ] **0.9.6 - Documentation and support readiness.** Review install/admin/recovery/privacy/security/compatibility/license docs against the candidate. Finalize release notes, issue routing, support ownership and incident procedures.
- [ ] **0.9.7 - Downloads and public services.** Stage signed ISO/raw images, Windows/macOS/Linux installers, Windows/universal macOS clients, checksums, signatures, source tag, SBOM and reproducible-build evidence. Prepare download/docs/status/support pages and verify every link. Publish only with release authority.
- [ ] **0.9.8 - Update operations.** Verify production update/rollback services, monitoring, alert routing, key/pin rotation and an exercised rollback decision path.
- [ ] **0.9.9 - Final signed-artifact acceptance.** Repeat clean install, supported upgrades, backup/restore, pairing, sustained connection and revocation against the exact signed artifacts. Archive signed evidence and confirm zero open ship-blockers.

## 1.0 - General availability

- [ ] **1.0.0 - Approve and publish Bedrock OS 1.0.** Obtain release-owner go/no-go approval after all prior gates pass; publish the verified artifacts, exact source tag, checksums, signatures, SBOM, licenses, documentation, release notes and support/status services. Verify public downloads and operational monitoring. **Gate:** explicit release-owner approval. Completion means the full signed, tested, recoverable product is available for installation.

## Traceability to the previous checklist

| Previous items | New coverage |
| --- | --- |
| 0.2.1-0.2.3 | 0.8.1-0.8.3 |
| 0.3.1-0.3.3 | 0.8.4-0.8.5 |
| 0.5.1-0.5.3 | 0.8.6-0.8.8 |
| 0.6.1 (completed relay implementation) | Retained baseline; installed acceptance in 0.6.5-0.6.6 |
| 0.6.2-0.6.8 | 0.6.1-0.6.9 |
| 0.7.1-0.7.8 | 0.7.1-0.7.8 and production signing in 0.9.5 |
| 0.8.1-0.8.2 | 0.8.9 |
| 0.9.1-0.9.6 | 0.9.1-0.9.6 |
| 1.0.1-1.0.5 | 0.9.5-0.9.7 and 1.0.0 |
| 1.0.6-1.0.8 | 0.9.8-0.9.9 and 1.0.0 |
