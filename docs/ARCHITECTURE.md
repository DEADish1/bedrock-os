# Bedrock Server OS architecture decision record

Status: accepted for implementation; changes require a recorded architecture decision and changelog entry.

## System foundation

- Base: Debian 13 stable (`trixie`), amd64.
- Kernel: Debian stable kernel stream, pinned per Bedrock release and advanced only through tested image builds.
- Init/service management: systemd.
- Boot: UEFI with systemd-boot and two bootable system slots.
- System image: immutable, signed, read-only root protected with dm-verity.
- Persistence: dedicated configuration/state partition plus separate user storage pools. Runtime state must never make the system image non-reproducible.
- Updates: signed release metadata, verified image download, inactive-slot installation, health-confirmed promotion, and automatic/manual rollback. UKIs carry monotonic `IMAGE_VERSION` metadata; systemd-boot selects the newest viable image and moves an entry behind its fallback when its counted attempts reach zero.
- Builds: reproducible CI image pipeline producing ISO, raw USB image, SBOM, provenance, SHA-256 checksums, and signatures.
- Disk contract: `os/layout/bedrock-amd64.json` defines ESP, root A/B, matching dm-verity and signature partitions, and growing persistent state. Root slot selection is bound to the signed root hash rather than an ambiguous first matching partition.

## Storage and NAS

- Primary pool technology: OpenZFS on Linux.
- File sharing: Samba/SMB first; NFS evaluated behind an explicit enablement flow.
- Disk health: `smartmontools`, NVMe health data, temperature/alert collection, and direct-drive identity.
- Bedrock stores intent and friendly metadata in SQLite but treats ZFS and the operating system as authoritative state.
- Pool layout decisions must explain failure tolerance, usable capacity, expansion limits, and recovery consequences before creation.

## Virtual machines and images

- Hypervisor: Linux KVM.
- Machine emulator/device model: QEMU.
- Management boundary: libvirt, using its domain, storage, network, device, snapshot, and secret models.
- Firmware: OVMF UEFI for supported guests.
- Remote console: SPICE or VNC behind Bedrock authorization; never directly exposed to the public network.
- Image operations: `qemu-img` in a constrained worker with format validation, size limits, checksums, and no untrusted image mounting in the host namespace.
- Passthrough: VFIO with IOMMU validation and explicit host-impact warnings.

## Bedrock service and API

- Core daemon: Rust, running as a restricted system service.
- API: versioned HTTPS/Unix-socket API with generated schema, capability-based authorization, structured errors, idempotent mutations, and task progress.
- Privilege: a small audited privileged helper exposes allowlisted operations; the web service does not run as root.
- State: SQLite in WAL mode for users, settings, tasks, audit records, paired devices, and UI metadata. Secrets use OS-protected encrypted storage and are never logged.
- Eventing: server-sent events or WebSocket notifications over the authenticated API.
- UI: React/TypeScript shared between browser management and desktop clients.

## Local and remote identity

- Local administration: Bedrock accounts with modern password hashing, secure recovery codes, session rotation, CSRF protection, and optional WebAuthn after baseline auth.
- Google alternative: OpenID Connect Authorization Code flow with PKCE. Google proves identity only; it receives no storage inventory, filenames, VM data, or server credentials.
- Pairing: one-time QR/manual code, short expiry, explicit approval on an already trusted session, and a unique device keypair.
- Device trust: per-device credentials with name, creation time, last use, rotation, and immediate revocation.

## Remote transport and clients

- Transport: WireGuard-based encrypted device tunnels.
- Connectivity: direct peer path where possible; authenticated relay fallback without exposing an inbound management port.
- Coordination service: stores routing/presence and public-key material only; it cannot decrypt server traffic.
- Desktop clients: Tauri 2 with a Rust core and the shared React UI, signed for Windows and notarized/universal for macOS.
- Client secrets: Windows credential protection and macOS Keychain; no raw private keys in web storage.
- Updates: signed desktop update channel with rollback protection.

## Security boundaries

- Browser/UI input is untrusted.
- Uploaded VM/disk images are untrusted.
- VMs and applications are isolated workloads, not trusted extensions of Bedrock.
- Storage mutation, update, pairing, passthrough, and destructive actions require server-side authorization and audit records.
- Network services bind to the minimum necessary interfaces and remain firewall-denied by default.
- Production release requires threat models, SBOMs, dependency scanning, signing-key procedures, penetration testing, and recovery drills.

## Deferred choices

- ARM64 host support.
- Container/application catalog format.
- NFS and Time Machine defaults.
- WebAuthn/passkeys.
- Relay hosting model and commercial operating plan.

## Primary references

- Debian stable release information: https://www.debian.org/releases/stable/
- OpenZFS documentation: https://openzfs.github.io/openzfs-docs/
- libvirt virtualization API and QEMU/KVM driver: https://libvirt.org/ and https://libvirt.org/drvqemu.html
- Linux dm-verity documentation: https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/verity.html
- WireGuard protocol: https://www.wireguard.com/protocol/
- OpenID Connect Core 1.0: https://openid.net/specs/openid-connect-core-1_0-18.html
- Tauri security model: https://v2.tauri.app/security/
