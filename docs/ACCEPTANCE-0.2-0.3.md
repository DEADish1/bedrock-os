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
