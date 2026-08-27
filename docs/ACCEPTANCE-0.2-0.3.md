# Bedrock 0.2 and 0.3 final acceptance bundle

Bedrock 0.2 and 0.3 may be declared complete only after the required physical and cross-hypervisor observations exist for one exact signed amd64 image. Automated fixture results prove the validators and write engines, but they cannot satisfy this release gate.

## Required reports

Keep six separate, privacy-reviewed JSON reports:

1. VMware UEFI boot, inventory, health, and persistent reboot.
2. Hyper-V Generation 2 UEFI boot, inventory, health, and persistent reboot.
3. Physical Intel UEFI boot, inventory, health, and persistent reboot.
4. Physical AMD UEFI boot, inventory, health, and persistent reboot.
5. One approved disposable removable drive written, fully reread, synchronized, safely removed, booted on supported UEFI hardware, and observed opening the guided installer.
6. One approved disposable internal system disk installed without a terminal, booted from the target, completed first-run setup, and retained state after reboot.

Use the procedures and example reports in `docs/BOOT-TEST-MATRIX.md`, `docs/INSTALLER-REAL-DEVICE-ACCEPTANCE.md`, and `docs/ON-SERVER-INSTALL.md`. Never include serial numbers, MAC addresses, IP addresses, usernames, hostnames, or free-form notes.

## Deferred desktop acceptance — 2026-08-26

The project owner intentionally deferred these six hardware acceptance sessions to a later desktop session. This is a scheduling note, not acceptance evidence: v0.2 remains at seven of eight requirements and v0.3 remains at six of eight requirements until all six reports above pass the final bundle check.

Resume with one exact verified signed amd64 image and use its SHA-256 for every report. For each VMware, Hyper-V, physical Intel, and physical AMD session, run the following on the first healthy boot, reboot the same installed disk, and complete the report on the second healthy boot:

```sh
sudo bedrock-boot-acceptance prepare vmware IMAGE_SHA256
sudo bedrock-boot-acceptance complete path/to/report.json
```

Replace `vmware` with `hyper-v` or `physical` for the matching session. Then complete the approved disposable USB and disposable internal system-disk sessions and run the one-command release gate below with all six reports.

This note does not authorize writing to any physical disk. At test time, the operator must separately identify and explicitly approve each exact disposable target containing no needed data.

### Prepare the evidence folder

After the desktop installer has verified the downloaded image signature and checksum, bind a new evidence folder to that exact file:

```sh
sh os/scripts/bedrock-acceptance-workspace.sh init \
  path/to/verified-bedrock.iso evidence/0.2-0.3
```

The helper calculates and stores the image SHA-256, prints the six required filenames, and does not open or write any disk. Reusing the folder with a different image is rejected. As reports are collected, check the remaining work with:

```sh
sh os/scripts/bedrock-acceptance-workspace.sh status evidence/0.2-0.3
```

The status command validates every report that is present, labels missing or invalid roles, and runs the complete release gate only when all six distinct reports match the folder's image SHA-256.

### Generate the short-lived desktop kit

When the hardware sessions are ready to begin, manually run the **Bedrock OS image** GitHub workflow on the exact acceptance branch with **protected_writer_acceptance** selected. After both reproducible builders and the raw-image boot/rollback tests pass, the workflow creates a seven-day `bedrock-0.2-0.3-acceptance-*` artifact containing:

- the exact acceptance-only ISO, detached signed manifest, and embedded-trust Linux desktop installer;
- the image/build/signing metadata and public ephemeral acceptance certificate;
- this runbook, the platform procedures, the evidence-folder helper, and all final validators.

The kit is deliberately not created by ordinary builds. It contains a physical-media-capable installer, uses a short-lived development trust chain, and is explicitly not release-eligible. Creating or downloading it does not authorize a disk write; the exact disposable target still requires separate approval during the test.

## One-command release gate

After each individual report passes its documented validator, run the complete bundle check from the repository root:

```sh
sh os/tests/validate-0.2-0.3-acceptance.sh \
  IMAGE_SHA256 \
  evidence/vmware.json \
  evidence/hyper-v-generation-2.json \
  evidence/physical-intel.json \
  evidence/physical-amd.json \
  evidence/disposable-usb.json \
  evidence/disposable-system-install.json
```

The command rejects fixture mode, write-only or unbooted media, indirect or reused report files, missing checks, wrong platform roles, Linux partition paths presented as whole removable devices, unknown or private fields, and any report that names a different image SHA-256. A passing result proves that the reports are complete and internally consistent; it does not create physical evidence or independently prove that the observations were performed. The reviewer must compare each report with the named test session before closing the roadmap checkboxes.

No acceptance procedure may select a disk automatically. The person conducting a destructive test must identify an exact disposable target containing no needed data and approve that target through the platform-specific confirmation flow.
