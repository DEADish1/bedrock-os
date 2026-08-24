# Bedrock OS image builder

This directory is the reproducible-image source for Bedrock Server OS. It uses Debian `live-build` and must run in a Debian 13 environment with root privileges. The configuration is source-controlled; generated `live-build` output is not.

## Outputs

- `bedrock-os-amd64.iso`
- `bedrock-os-amd64.iso.sha256`
- `bedrock-build-manifest.json`
- `build.log`

The first image is a development/live foundation, not yet an installable 1.0 system. The two-slot immutable system layout and dm-verity integration are subsequent 0.2 work.

## Build on Debian 13

```sh
sudo ./os/scripts/build-image.sh
./os/scripts/verify-artifacts.sh os/out
```

Use `SOURCE_DATE_EPOCH` to reproduce a release timestamp. CI derives it from the source commit time. Mirrors affect availability and transfer speed but packages are constrained to Debian 13 and the package snapshot recorded in the generated manifest.

CI runs two clean ISO replicas and `scripts/compare-reproducible-builds.sh` requires their image bytes, resolved package locks, and build manifests to match exactly. Raw images use ephemeral development signing keys in CI and are therefore validated for structure, verified boot, updates, and rollback rather than compared byte-for-byte.

## Configuration

- `build.env`: version, distribution, architecture, and image identity.
- `auto/config`: canonical `live-build` configuration.
- `config/package-lists/bedrock.list.chroot`: packages included in the image.
- `config/includes.chroot/`: files copied into the root filesystem.
- `scripts/validate-config.sh`: safe validation that can run without root or `live-build`.
- `layout/bedrock-amd64.json`: canonical UEFI A/B system-disk contract.
- `scripts/validate-layout.sh`: validates partition order, roles, GUIDs, mutability, rollback policy, and minimum capacity.
- `boot/bedrock-cmdline`: minimal verified-boot kernel policy shared by both slots.
- `scripts/build-uki.sh`: creates a slot-bound, Secure Boot-signed unified kernel image.
- `scripts/validate-boot.sh`: prevents ambiguous root selection and unsigned UKI configuration.
- `scripts/build-verified-root.sh`: deterministically creates an EROFS root, detached dm-verity tree, root hash, PKCS#7 signature, and signature-partition JSON.
- `scripts/verify-verified-root.sh`: verifies the filesystem/hash pairing and the detached signature before assembly.
- `scripts/assemble-disk-image.sh`: creates the canonical GPT image, installs both verified slots and UKIs, formats persistent state, and emits a checksum.
- `scripts/verify-disk-image.sh`: checks disk size, GPT integrity, partition ordering, names, and standard type GUIDs.
- `installer/validate-install-target.sh`: validates one exact internal system-disk selection against fresh Linux inventory and the canonical minimum size without opening a disk.
- `installer/create-install-plan.sh`: creates a checksum-bound, review-only partition plan that remains explicitly disconnected from privileged writing.
- `installer/simulate-install-image.sh`: exercises verified image writing, GPT relocation, persistent-state growth, and final validation only on a confined disposable regular file; it refuses block devices.
- `installer/protected-system-writer.rs`: disabled-by-default Linux writer stage that can exclusively open one freshly confirmed whole disk, recheck the exact packaged image, write, synchronize, and fully reread it only in an explicit production-trust build.
- `installer/finalize-protected-layout.sh`: identity-bound Linux finalizer that relocates GPT, grows and checks persistent state, and verifies the canonical partition contract after a successful protected raw write.
- `installer/stage-protected-installer.sh`: reproducibly stages or removes the complete protected installer package, fixed layout/scanner, integrity manifest, build-mode metadata, and gated helper for live-image construction.
- `installer/create-protected-install-request.sh` and `installer/preflight-protected-install.sh`: create and independently revalidate a bounded, expiring request with no caller-selected source or device path; preflight alone remains strictly non-writing.
- `config/includes.chroot/usr/lib/bedrock/mark-boot-healthy`: validates persistent state, records the healthy slot, and tells systemd-boot to bless it.
- `tests/test-uefi-boot.sh`: boots the raw image with OVMF/QEMU and requires an exact healthy-slot serial marker.
- `tests/validate-boot-test-report.sh`: validates privacy-safe acceptance evidence from VMware, Hyper-V, and physical Intel/AMD systems.
- `tests/test-ab-rollback.sh`: fails either slot on a disposable image, verifies all three counted attempts, and requires automatic recovery into the other healthy slot.
- `tests/test-update-install.sh`: verifies both a healthy signed update and a correctly signed but unbootable update, including automatic recovery to the previous slot.
- `scripts/create-update-bundle.sh`: creates a canonical manifest for the four inactive-slot artifacts and signs it with the protected update key.
- `config/includes.chroot/usr/lib/bedrock/verify-update-bundle`: rejects untrusted manifests, unexpected schemas, missing files, size changes, and checksum changes before installation.
- `config/includes.chroot/usr/sbin/bedrock-update`: writes a verified bundle only to the inactive root/verity/signature slots, verifies each device write, and arms its UKI for three health-gated attempts.
- `config/includes.chroot/usr/lib/bedrock/check-for-updates`: honors the persistent automatic-check preference, downloads only bounded HTTPS metadata, verifies its CMS signature and schema, and records availability without installing anything.
- `config/includes.chroot/usr/sbin/bedrock-update-settings`: shows or changes automatic checks and provides the manual `check-now` path; `bedrock-setup-updates` exposes the same choice to first-run setup.
- `scripts/build-raw-image.sh`: joins root-image, UKI, disk assembly, signing classification, and VM-test inputs into one guarded pipeline.
- `scripts/generate-development-keys.sh`: creates short-lived, clearly marked CI-only keys; artifacts made with them are never release eligible.
- `scripts/build-installed-initrd.sh`: creates the systemd/dracut initramfs used for slot-bound dm-verity activation; the ISO retains its separate live-media initramfs.
- `.github/workflows/os-image.yml`: clean CI build, verification, checksums, artifact upload, and provenance attestation.
