# Virtualization foundation

Bedrock uses KVM for hardware acceleration, QEMU for the machine model, libvirt's system connection as the management boundary, and OVMF for x86-64 UEFI guest firmware.

At boot, `bedrock-virtualization-capabilities.service` writes `/var/lib/bedrock/virtualization/capabilities.json`. A host is reported as supported only when all five independent checks pass: Intel VT-x or AMD-V is visible, `/dev/kvm` is a usable character device, the packaged QEMU binary is direct and executable, packaged OVMF firmware is direct and readable, and libvirt's `qemu:///system` connection responds. Missing capabilities are reported with stable reason codes rather than silently falling back to unaccelerated emulation.

This foundation does not authorize VM creation or mutation. The v0.5 lifecycle layer must still define bounded domain XML, resource reservations, storage ownership, networking, snapshots, deletion, audit state, and authorization before the roadmap integration item can be closed.

Production acceptance must prove the capability report on supported Intel and AMD hosts, create a UEFI guest through the system libvirt connection, confirm KVM acceleration, reboot the host, and verify that the guest definition and storage remain intact.
