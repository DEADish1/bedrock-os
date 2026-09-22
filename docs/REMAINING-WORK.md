# Bedrock OS remaining-work checklist

This is the fresh, actionable path from the current branch to a signed 1.0 release. Version numbers are target milestones, not claims that a release has shipped. A box closes only when the named acceptance evidence exists on the release-candidate build. `PROJECT-ROADMAP.md` retains the product requirements; this file breaks its open gates into smaller jobs. As of 2026-09-22, relay Settings changes are local and uncommitted, so they remain open here.

## 0.2.0 — Bootable foundation acceptance

- [ ] **0.2.1 — Physical Intel boot:** Boot the exact candidate ISO and USB image on a supported Intel UEFI system; capture hardware inventory, service health, persistent-state reboot, diagnostics, update, and rollback evidence. **Gate:** Intel machine and approved test disk.
- [ ] **0.2.2 — Physical AMD boot:** Repeat the same acceptance on supported AMD hardware, including virtualization and supported graphics detection. **Gate:** AMD machine and approved test disk.
- [ ] **0.2.3 — VM-platform boot matrix:** Boot the exact image on the supported hypervisors and record pass/fail by firmware, storage, NIC, display, and recovery mode. **Gate:** acceptance hosts.

## 0.3.0 — Installer and first-run acceptance

- [ ] **0.3.1 — USB writing:** On Windows, macOS, and Linux, enumerate a real removable target, verify signed download/checksum, require target-specific destructive confirmation, write, reread/verify, and boot it. Capture failed-media and interrupted-write behavior. **Gate:** disposable USB media and all three hosts.
- [ ] **0.3.2 — ISO/DVD guidance:** Publish tested ISO download and DVD instructions, including verification, firmware selection, and safe recovery guidance.
- [ ] **0.3.3 — Physical system-disk install:** From the live installer, select an approved disposable system disk, review destructive scope, install, reboot, complete first-run setup without a terminal, and verify persistent configuration and rollback. **Gate:** disposable physical system.

## 0.5.0 — VM release acceptance

- [ ] **0.5.1 — Linux guest:** On the exact release-candidate image, install and boot a Linux VM; verify acceleration, assigned CPU/RAM/storage/network, browser console, guest readiness, reboot persistence, and snapshot restore. **Gate:** acceptance host.
- [ ] **0.5.2 — Windows guest:** Repeat with a licensed Windows installer and required drivers; verify distinct guest isolation, console, agent readiness, reboot, and snapshot recovery. **Gate:** Windows media/license and acceptance host.
- [ ] **0.5.3 — Passthrough qualification:** On supported hardware, prove safe GPU and USB assignment/removal and refusal of host-critical devices. **Gate:** IOMMU-capable test hardware.

## 0.6.0 — Management interface and authenticated API

- [x] **0.6.1 — Complete the Settings relay change:** Guarded setup/disable is committed and pushed. The API, root broker, helper, and browser tests cover secret-free responses, root-only staging, exact confirmation, idempotency, strong ETag rejection, disable/re-enable, and failed-restart rollback. [Linux validation run 35729600235](https://github.com/DEADish1/bedrock-os/actions/runs/35729600235) passed; image reproducibility jobs are separate release evidence.
- [ ] **0.6.2 — API mutation inventory:** The [mutation audit](API-MUTATION-INVENTORY.md) maps the 33 packaged mutation method/path combinations and identifies the missing production browser gateway plus root-staged setup decisions. Package and verify the gateway, then implement or explicitly defer any remaining authenticated, bounded, auditable mutation. Do not close the broad roadmap API/UI items from read routes alone.
- [ ] **0.6.3 — Task and audit coverage:** Confirm every long-running or destructive operation emits bounded progress, terminal task state, and privacy-safe audit outcomes, including error/interruption paths. Relay configuration and disablement now emit bounded terminal events, including a failed-restart event; [Linux validation run 35730263089](https://github.com/DEADish1/bedrock-os/actions/runs/35730263089) passed. Other operation families still require a complete coverage audit.
- [ ] **0.6.4 — Cross-area UI acceptance:** Exercise Storage, VMs, Images, Apps, Connect, Backup, Hardware, Settings, Help, and Users against a real candidate server, including empty, stale, disconnected, denied, and partial-failure states.
- [ ] **0.6.5 — Browser mutation tests:** Cover each mutation family end to end with authentication, exact confirmation, stale ETag, idempotent replay/conflict, successful refresh, error handling, and no secret disclosure.
- [ ] **0.6.6 — Console acceptance:** Verify a real running guest through the embedded browser console, one-time token redemption, expiration, reconnect, and no token in URL, logs, or persisted state.
- [ ] **0.6.7 — Accessibility:** Run keyboard-only, screen-reader, 200–400% zoom/reflow, focus, status-announcement, and WCAG 2.2 AA manual/automated checks on supported browsers and physical devices. Record and fix findings. **Gate:** assistive-technology test environment.
- [ ] **0.6.8 — API contract/security:** Validate every implemented route against OpenAPI, bearer-token issue/revocation, authorization denial, request limits, response schemas, concurrent changes, and cross-area browser flows on the candidate image.

## 0.7.0 — Remote access and desktop clients

- [ ] **0.7.1 — Pairing end to end:** Complete client-facing QR/manual-code exchange through relay/direct ingress, local server approval, 10-minute/reboot expiry, one-time redemption, bad-code indistinguishability, and replay/rate-limit tests.
- [ ] **0.7.2 — Device sessions/revocation:** Prove distinct per-device keys, listing/rename/expiry, authenticated Noise session binding, long-lived API forwarding, immediate active-session termination on revoke, and reconnect rejection.
- [ ] **0.7.3 — Optional Google sign-in:** Implement the scoped OpenID Connect flow or document and approve its deferral from 1.0; ensure Google receives no server content, device inventory, or local API token. **Gate:** OAuth application credentials if included.
- [ ] **0.7.4 — Production relay/fallback:** Provision a production endpoint, test outbound-only TLS/Noise routing, fallback and network changes, relay outage/reconnect, hostile frame handling, and proof that no unsafe inbound port opens. **Gate:** production relay infrastructure/credentials.
- [ ] **0.7.5 — Windows client:** Build, package, sign, and acceptance-test pairing, connection, revocation, updates, certificate pinning, and OS-protected key storage. **Gate:** Windows signing and test environment.
- [ ] **0.7.6 — Universal macOS client:** Build/test both Apple Silicon and Intel slices, sign/notarize, and verify the same trust/update/storage behaviors. **Gate:** Apple hardware and signing/notarization authority.
- [ ] **0.7.7 — Client updates:** Verify authenticated update metadata, pin rotation, downgrade/replay rejection, interrupted update recovery, and no silent trust expansion.
- [ ] **0.7.8 — Independent remote-security review:** Obtain a third-party review and close pairing, authentication, transport, update, and revocation findings. **Gate:** independent reviewer.

## 0.8.0 — Recovery and operations acceptance

- [ ] **0.8.1 — UPS and maintenance:** On a supported physical UPS, verify low-battery shutdown, failed-quiesce handling, reboot recovery, and safe maintenance entry/exit with real guests and shares. **Gate:** controlled UPS discharge setup.
- [ ] **0.8.2 — Full restore drill:** Restore files, VM data/snapshots, configuration, credentials, and a failed system drive onto a clean replacement; verify hashes, boot, non-destructive pool import, and signed-off report. **Gate:** physical replacement hardware and backup media.

## 0.9.0 — Release candidate

- [ ] **0.9.1 — Upgrade matrix:** Test every supported pre-1.0 source version to the exact candidate, including schema migration, data preservation, rollback, and interrupted upgrade recovery.
- [ ] **0.9.2 — Reliability campaign:** Record soak/load, abrupt power loss, disk failure/rebuild, network loss/recovery, and restore behavior on candidate hardware; triage every ship-blocker. **Gate:** hardware and sustained test time.
- [ ] **0.9.3 — Security campaign:** Complete penetration test, dependency and SBOM review, vulnerability intake/response exercise, and closure of critical/high findings. **Gate:** independent security reviewer.
- [ ] **0.9.4 — Release signing:** Establish production keys and sign/notarize OS images, installers, clients, update manifests, checksums, and release artifacts; verify from clean systems. **Gate:** signing authority and credentials.
- [ ] **0.9.5 — Beta:** Recruit representative testers, distribute a verified candidate, capture install/upgrade/recovery/usability findings, fix blockers, and publish candidate checksums. **Gate:** beta participants.
- [ ] **0.9.6 — Release documentation review:** Recheck installation, admin, recovery, privacy/security, compatibility, licenses, support, and issue-routing docs against the exact candidate; publish corrections and release notes.

## 1.0.0 — General availability

- [ ] **1.0.1 — OS artifacts:** Publish signed ISO and raw USB image with independently verified SHA-256 checksums and provenance.
- [ ] **1.0.2 — Installer artifacts:** Publish signed Windows, macOS, and Linux installers and verify installation from clean supported hosts.
- [ ] **1.0.3 — Client artifacts:** Publish signed Windows and universal macOS clients after remote acceptance.
- [ ] **1.0.4 — Source/evidence:** Tag the exact source, publish SBOM, licenses, reproducible-build instructions, signatures, and archived build/acceptance evidence.
- [ ] **1.0.5 — Public services:** Launch download site, documentation, status page, support channels, and release notes; verify links and incident ownership.
- [ ] **1.0.6 — Update operations:** Confirm production update/rollback services, monitoring, alert routing, and a tested rollback decision path.
- [ ] **1.0.7 — Final acceptance:** Repeat clean install, upgrade, backup/restore, pairing, live connection, and revocation against the exact signed release artifacts.
- [ ] **1.0.8 — Go/no-go:** Confirm no open ship-blocking defects, archive signed acceptance records, and obtain explicit general-availability approval. **Gate:** release owner.
