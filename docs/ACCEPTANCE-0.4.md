# Bedrock 0.4 storage and NAS acceptance

Bedrock 0.4 is accepted only when the normal configuration suite and the dedicated disposable Linux storage workflow both pass for the same revision. No test may use an existing host disk.

## Automated contract evidence

- Disk, SMART, temperature, Linux RAID, ZFS, controller, StorCLI member/logical-volume/cache, rebuild, alert, and audit contracts.
- Exact layout and failure-tolerance planning for ZFS mirror/RAID-Z1/RAID-Z2 and Linux RAID 1/5/6/10.
- Protected create, expand, scrub/check, export, import, and replace state transitions with exact confirmation and interruption-before-commit behavior.
- Terminal-free guided storage selection, review, cancellation, and incorrect-confirmation rejection.
- Users, groups, membership, root-readable password rotation, secret redaction, datasets, ZFS quota, ACL, snapshot, SMB, NFS, recycle, and quota-bounded Time Machine contracts.
- Persistent boot activation and atomic SMB/NFS runtime rendering on the immutable OS.
- Checksum manifest creation and detection of added, removed, or modified dataset content.

Run the complete local contract suite:

```sh
./os/scripts/validate-config.sh
```

## Disposable Linux integration evidence

The `Storage and NAS acceptance` GitHub workflow installs current storage tools on an isolated Ubuntu runner. It creates only temporary regular files and loop devices, then exercises real OpenZFS and Linux RAID creation, data writes, scrub/check, an offline or failed member, replacement and rebuild, export/stop, import/assembly, and SHA-256 verification. It also validates the generated Samba configuration with Samba's own parser.

The workflow must be green before changing the 0.4 roadmap exit state. A skipped storage tool, unavailable kernel module, unverified checksum, or cleanup failure is a failed acceptance run.

## Physical hardware follow-up

Physical controller acceptance remains model-specific. A controller without a supported management tool must continue to report limited visibility. Adding a supported controller model requires archived evidence for controller status, member health, cache or battery protection, logical volume health, and rebuild progress; Bedrock must never infer those details from the logical disk alone.

Abrupt-power testing on release hardware remains part of the 0.9 release-candidate soak and power-loss gate. The 0.4 test covers the storage-operation durability boundary and filesystem/pool recovery without claiming that a Mac-hosted test physically removed server power.
