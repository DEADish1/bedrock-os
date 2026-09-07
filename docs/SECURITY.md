# Security architecture and operations

Bedrock uses an immutable, dm-verity-protected system image with signed UEFI artifacts, counted A/B boot attempts, signed update metadata, and health-gated promotion. Development keys and unsigned preview clients are never release eligible. Production signing keys must stay outside ordinary build workspaces.

The local management API runs without root on a permission-restricted Unix socket. Bearer credentials are stored as bounded hashes and are immediately rejected after revocation. A separate root action broker authenticates its Unix peer from kernel credentials, accepts only bounded allowlisted schemas, invokes fixed-path helpers without a shell, suppresses command output, and persists bounded request hashes for idempotent replay and conflict rejection. Privileged operations remain separate, fixed-path helpers with strict schemas, stable identities, exact confirmations, locking, fresh authoritative-state checks, atomic state replacement, and rollback where possible.

VMs use KVM/libvirt and local-only console sockets. Uploaded images are inspected without mounting and reject backing chains, encryption, changed bytes, and unsafe archive members. Applications are digest-pinned, non-root Podman containers with read-only roots, all capabilities dropped, no privilege escalation, explicit limits, controlled networking, and one confined writable data mount.

Storage operations reject the running system disk, mounted or indirect devices, stale plans, unsafe identities, and topology changes. Backup and notification credentials live outside public state. Diagnostics exclude secrets, user data, command arguments, and raw identifiers. Maintenance mode fails closed around mutating entry points and quiesces managed workloads before poweroff or service work.

Remote access is not release-ready. Its required protocol, client-key storage, relay privacy, rekeying, revocation, and review gates are defined in the [remote-access threat model](REMOTE-ACCESS-THREAT-MODEL.md). Do not expose unfinished remote services or claim end-to-end protection before those tests and the third-party review pass.

Release security requires reproducible artifacts, an SBOM, dependency and vulnerability review, production signatures, penetration testing, restore and failure drills, and archived acceptance evidence. Report vulnerabilities according to the repository [security policy](../SECURITY.md).
