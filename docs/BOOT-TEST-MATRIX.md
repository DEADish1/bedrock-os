# Bedrock 0.2 boot-test matrix

The final 0.2 release gate requires the same signed amd64 image to boot on every row below. QEMU is automated in CI; the remaining rows require their named platform or physical machine.

| Platform | Required coverage | Status |
| --- | --- | --- |
| QEMU/KVM with OVMF | UEFI boot, persistent state, health marker, A/B rollback | Passed in CI |
| VMware | UEFI boot, storage/NIC discovery, persistent reboot | Pending |
| Hyper-V Generation 2 | UEFI boot, storage/NIC discovery, persistent reboot | Pending |
| Physical Intel x86-64 | UEFI boot, CPU/RAM/disk/NIC/GPU inventory, persistent reboot | Pending |
| Physical AMD x86-64 | UEFI boot, CPU/RAM/disk/NIC/GPU inventory, persistent reboot | Pending |

## Test procedure

1. Verify the image SHA-256 against the workflow artifact before booting it.
2. Use UEFI mode. Record whether Secure Boot is disabled or enabled with a trusted Bedrock key.
3. Boot the image and wait for `BEDROCK_BOOT_HEALTHY slot=A` on the serial console or diagnostics view.
4. Confirm `/var/lib/bedrock/hardware/inventory.json` exists and contains CPU, memory, disk, and network records.
5. Reboot without changing the disk and confirm the system remains healthy and persistent state is retained.
6. Copy `os/tests/boot-test-report.example.json`, change `mode` to `physical`, enter the observed values, record `generation-2` only for Hyper-V, and run:

   ```sh
   sh ./os/tests/validate-boot-test-report.sh path/to/report.json
   ```

The validator rejects fixture-mode reports during normal acceptance. Do not add serial numbers, MAC addresses, public IP addresses, usernames, hostnames, notes, or other personal data to reports committed to GitHub.

## Completion rule

The roadmap checkbox may be marked complete only after schema-2 physical-mode passing reports exist for VMware, Hyper-V Generation 2, one physical Intel system, and one physical AMD system, all naming the same verified image SHA-256, in addition to the automated QEMU result.

Before closing 0.2 or 0.3, combine these reports with the removable-media and installed-system reports using `docs/ACCEPTANCE-0.2-0.3.md`. The bundle validator enforces the four distinct boot roles and one exact image hash across every report.
