# Troubleshooting

Start by preserving evidence: record the Bedrock version, image checksum, time, affected subsystem, and exact visible error. Do not retry destructive actions repeatedly, edit generated state, force-import storage, or start guests against uncertain disks.

## Server does not boot

Confirm UEFI mode, supported x86-64 hardware, and the selected Bedrock entry. The counted A/B boot policy should fall back after an unhealthy slot exhausts its attempts. If neither slot reaches the healthy marker, stop and use verified installation media; do not reformat the data pool. See [bare-metal recovery](BARE-METAL-RECOVERY.md).

## Storage is degraded or unavailable

Treat `critical`, `degraded`, `faulted`, and `limited` distinctly. Identify devices by stable `/dev/disk/by-id` paths and compare current topology with the reviewed plan. Do not replace a second member while reconstruction is active. Hardware RAID reported as `limited` requires supported controller tooling before member or cache health can be claimed. Use the guided recovery flow and verify dataset integrity afterward.

## Interface or API is unavailable

Use the local console. Check `systemctl status bedrock-api.service` and whether `/run/bedrock-api/api.sock` is a socket with the packaged ownership. A missing, malformed, or revoked bearer token returns 401; malformed subsystem state returns an independent 503 without making unrelated dashboard components unavailable. Never change socket permissions to make it network-accessible.

## VM or application will not start

Review the capability report, host CPU/memory reservation, managed image checksum, and current storage health. VM definitions require KVM, libvirt, OVMF, and a usable `/dev/kvm`. Applications require their exact pinned image digest and resource limits. Do not add host networking, privileged mode, arbitrary mounts, or devices to work around a failure.

## Update or backup fails

An update must match signed metadata, the inactive-slot layout, and every artifact checksum. Keep the current healthy slot and do not bless a failed boot. Backup failures do not prove prior snapshots are unusable; inspect the bounded result, correct repository connectivity or credentials, rerun, then perform a restore into a new destination. Never overwrite the original during diagnosis.

## Power or maintenance interruption

If maintenance state is `entering`, `active`, or `failed`, mutations remain blocked. Resolve any guest/application that failed to stop, then use the exact maintenance exit command. After unexpected power loss, verify pools, arrays, shares, guests, applications, and backup state before resuming writes.

If these steps do not isolate the fault, read the [support policy](../SUPPORT.md) and generate a [redacted diagnostic bundle](DIAGNOSTICS.md). Security-sensitive symptoms must use private vulnerability reporting.
