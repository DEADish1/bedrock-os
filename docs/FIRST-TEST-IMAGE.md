# First Bedrock test image

This image is for controlled acceptance only. It is not a release and its development trust certificate is short-lived.

## Artifacts

- Reproducible base-image evidence: [GitHub Actions run 34015349856](https://github.com/DEADish1/bedrock-os/actions/runs/34015349856), artifact `bedrock-os-amd64-1`.
- Physical-writer acceptance kit: [download artifact 9990258791](https://github.com/DEADish1/bedrock-os/actions/runs/34033836329/artifacts/9990258791), named `bedrock-0.2-0.3-acceptance-34033836329`. The workflow-uploaded ZIP is 1,034,193,590 bytes with SHA-256 `0fe4f82da5fb8c097608dda05133aedf8c6239dcf15623f749c7c23dec724ffa` and expires September 13, 2026.

Download the named artifact while it is available. Verify the ISO with `sha256sum -c bedrock-os-amd64.iso.sha256`. To verify the raw disk artifact, decompress `bedrock-os-amd64.raw.zst` to `bedrock-os-amd64.raw`, then run `sha256sum -c bedrock-os-amd64.raw.sha256`. Use only files from one run and one recorded SHA-256 throughout acceptance.

## Safe test order

1. Start with VMware: UEFI firmware, at least 4 GiB RAM, two virtual CPUs, and a disposable virtual disk of at least 32 GiB.
2. Repeat with Hyper-V Generation 2 and a new disposable virtual disk.
3. Only after both virtual sessions pass, write one explicitly approved disposable USB drive containing no needed data and boot it on supported UEFI hardware.
4. Run the physical boot session on one Intel x86-64 system and one AMD x86-64 system. Do not select an internal system disk during these boot-only sessions.
5. Run the separate on-server installation procedure only on an explicitly approved disposable internal disk containing no needed data.

For VMware, Hyper-V, Intel, and AMD, follow `BOOT-TEST-MATRIX.md`: prepare the collector on the first healthy boot, reboot the same installed disk, complete the report on the second healthy boot, and validate it. Use the exact role filenames printed by `bedrock-acceptance-workspace.sh init`.

For the removable-drive and system-disk sessions, follow `INSTALLER-REAL-DEVICE-ACCEPTANCE.md` and `ON-SERVER-INSTALL.md`. The operator must separately approve each exact destructive target; possession of the kit is not authorization to erase any disk.

Finally, run the six-report command in `ACCEPTANCE-0.2-0.3.md`. Do not add serial numbers, MAC addresses, IP addresses, usernames, hostnames, or free-form notes to evidence.
