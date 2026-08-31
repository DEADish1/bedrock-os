# Virtualization foundation

Bedrock uses KVM for hardware acceleration, QEMU for the machine model, libvirt's system connection as the management boundary, and OVMF for x86-64 UEFI guest firmware.

At boot, `bedrock-virtualization-capabilities.service` writes `/var/lib/bedrock/virtualization/capabilities.json`. A host is reported as supported only when all five independent checks pass: Intel VT-x or AMD-V is visible, `/dev/kvm` is a usable character device, the packaged QEMU binary is direct and executable, packaged OVMF firmware is direct and readable, and libvirt's `qemu:///system` connection responds. Missing capabilities are reported with stable reason codes rather than silently falling back to unaccelerated emulation.

This foundation does not authorize VM creation or mutation. The v0.5 lifecycle layer must still define bounded domain XML, resource reservations, storage ownership, networking, snapshots, deletion, audit state, and authorization before the roadmap integration item can be closed.

`create-vm-plan` is the first lifecycle boundary. It accepts a strict schema-1 request, requires the boot capability report to be fully ready, checks the hardware inventory and all existing managed allocations, reserves two logical CPUs and 2 GiB of memory for Bedrock, rejects duplicate or unsafe names and out-of-range resources, and emits a root-readable review-only plan. The plan always contains `mutation_authorized: false`; it cannot invoke libvirt or create storage.

`render-vm-domain` deterministically compiles a valid review plan into a root-readable, name-bound domain definition. The fixed policy uses KVM, x86-64 Q35, Secure Boot-capable OVMF pflash, host-passthrough CPU, virtio disk/network/video/balloon devices, the libvirt default network, and a local-only SPICE listener. Disk and NVRAM paths are derived only from the already validated name. The renderer cannot call libvirt, create a disk, enable autostart, or start a guest.

`register-vm` is the first mutation boundary. It requires a separate strict authorization record containing the exact confirmation phrase and SHA-256 hashes of both the reviewed plan and deterministic definition. As root, it accepts only fixed name-bound paths, serializes registrations, creates one bounded QCOW2 disk, defines the persistent system-libvirt guest, records the allocation atomically, and rolls back the definition and disk on failure. Registration never starts the guest.

Production acceptance must prove the capability report on supported Intel and AMD hosts, create a UEFI guest through the system libvirt connection, confirm KVM acceleration, reboot the host, and verify that the guest definition and storage remain intact.
