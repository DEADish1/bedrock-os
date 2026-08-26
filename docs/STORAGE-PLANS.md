# Storage and NAS operations

Bedrock validates a proposed ZFS or Linux MD layout before any privileged operation. The original `create-storage-plan` remains a command-free review contract for the management interface. The protected `bedrock-storage` service independently validates the final request, exact confirmation, managed state, operation ordering, exclusive lock, whole-device identity, mounted/read-only/system-disk status, and current SMART failure state immediately before applying a change.

Supported review layouts are ZFS mirror, RAID-Z1, and RAID-Z2 plus Linux MD RAID 1, 5, 6, and 10. Selected disks must be present exactly once in a fresh inventory, unused, writable, unmounted, non-system, non-removable, at least 64 GiB, and use the same logical sector size. Direct disks require known-good health. Hardware RAID logical volumes must remain explicitly unknown in the current contract and can enter only the acknowledged advanced review path. The confirmation text must name the pool, backend, layout, and every selected device path exactly.

The planner rejects mixing direct disks with hardware RAID logical volumes and rejects Linux MD layered on hardware RAID. ZFS review on hardware RAID requires an advanced acknowledgement and carries a warning that physical-member, cache/battery, and rebuild visibility may be hidden.

`bedrock-storage plan` covers creation, protected-vdev or Linux RAID expansion, scrub/check, export, import, and disk replacement. `bedrock-storage apply` is root-only, serializes mutations, records a secret-free audit event, and updates durable managed state only after the underlying storage tool succeeds. ZFS expansion adds a complete protected mirror or RAID-Z vdev; it never adds an unprotected single disk. Linux RAID 10 member-count changes remain blocked because that reshape is not accepted as a safe general workflow.

`bedrock-storage-guided` provides the local-console workflow. It explains protection choices, lists healthy candidate disks, requires the exact pool/layout/device phrase, displays the protected plan, and performs a final confirmation. The privileged executor repeats safety checks rather than trusting the interface.

## NAS resources

`bedrock-nas` manages local NAS users, groups, group membership, password rotation, datasets, quotas, ACLs, shares, snapshots, and snapshot removal. Passwords travel only through a bounded direct file, are copied with root-only permissions, and never appear in a request, command argument, state file, or audit event.

OpenZFS datasets support byte quotas and manual snapshots. Samba/SMB is the primary file-sharing protocol; NFS is available only when explicitly selected. Shares can be read-only or writable, optionally preserve deleted files in a per-user recycle directory, and can be configured as quota-bounded SMB Time Machine targets. SMB2.1 is the minimum protocol and guest mapping is disabled.

Because Bedrock's system image is immutable, `render-nas-services` writes Samba and NFS runtime configuration to persistent Bedrock state. Storage activation assembles and mounts managed Linux RAID arrays first, renders shares atomically, and then activates exports. Samba is ordered after that activation and reads the persistent generated configuration.

## Health and recovery

Storage health includes disks, non-waking SMART status, temperatures, Linux RAID state and recovery progress, ZFS pools, and hardware RAID discovery. When StorCLI is installed, Bedrock normalizes controller, physical-member, logical-volume, cache-protection, and rebuild data. Without supported vendor telemetry, hardware RAID is explicitly reported as limited rather than healthy.

`storage-integrity create` records a bounded SHA-256 manifest for a dataset tree, rejecting symbolic links and unsafe names. `storage-integrity verify` detects added, removed, resized, or modified files. Automated recovery tests cover operation interruption before durable commit, degraded storage, disk replacement, rebuild/check, export/import, snapshot behavior, and post-recovery integrity. The Linux acceptance workflow additionally exercises disposable real ZFS and Linux RAID devices; it never targets a host disk.
