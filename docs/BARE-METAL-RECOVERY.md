# Configuration export and bare-metal recovery

Bedrock configuration backups deliberately exclude user files, VM disks, API credentials, remote-pairing keys, logs, and recovery secrets. Copy those data sets with a separately encrypted backup plan.

Create an owner-readable, version-bound configuration archive as root:

```sh
bedrock-config-backup export "EXPORT BEDROCK CONFIGURATION" /mnt/backup/bedrock-config.tar.gz
```

For bare-metal recovery, install the same Bedrock version on the replacement system, import and verify the storage pool without creating new filesystems, copy the archive locally, then run:

```sh
bedrock-config-backup restore "RESTORE BEDROCK CONFIGURATION" /mnt/backup/bedrock-config.tar.gz
reboot
```

Restore rejects oversized, indirect, linked, duplicate, unexpected, changed, malformed, or version-mismatched content. Each restored file is staged before replacement. Existing configuration is retained under `/var/lib/bedrock/recovery/config-TIMESTAMP`; keep it until shares and virtual machines have been checked after reboot. Import storage and restore data before enabling shares or starting guests. Rotate API and remote-client credentials after recovery instead of restoring old secret material.
