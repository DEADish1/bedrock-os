# Guest operating-system compatibility

This document defines what Bedrock may present as supported. A guest is not supported merely because QEMU can start it. Bedrock must also provide an install path, required virtual hardware and drivers, update-safe lifecycle operations, and acceptance evidence.

## Windows guests

Bedrock's intended supported Windows baseline is 64-bit Windows 11 and Windows Server 2022/2025 on x86-64 hosts. Windows 10 is not a release target because its general support ended before Bedrock 1.0. Windows on Arm is not supported by the current x86-64 machine model.

Windows installation uses Bedrock's UEFI/Secure Boot guest, a VirtIO system disk and network adapter, and the generic browser display. The administrator must obtain a trusted, signed `virtio-win.iso` from the upstream VirtIO Windows project and attach it as read-only installation media. Bedrock does not silently download or redistribute a changing third-party driver image.

During Windows Setup, choose **Load driver** if the installer cannot see the system disk, then select the matching signed AMD64 `viostor` driver from the VirtIO ISO. After Windows starts, install the signed guest-tools package or the individual AMD64 drivers needed by the VM:

- `viostor`: VirtIO block storage used by the Bedrock system disk.
- `NetKVM`: VirtIO network adapter.
- Balloon driver/service: cooperative memory reporting and ballooning.
- QEMU guest agent: orderly guest integration when Bedrock adds the agent channel and authenticated API controls.

Do not disable Secure Boot or Windows driver-signing enforcement to load an unsigned or test-signed build. Driver updates should follow the same snapshot, backup, signature verification, install, reboot, and Device Manager verification process as other privileged Windows drivers. The upstream project documents its distributed ISO and guest-tools installer in the [VirtIO Windows driver repository](https://github.com/virtio-win/kvm-guest-drivers-windows) and [driver installation guide](https://github.com/virtio-win/kvm-guest-drivers-windows/wiki/Driver-installation).

Windows 11 must not be labeled supported until Bedrock adds a persistent software TPM 2.0 to the managed domain and completes install, reboot, snapshot, restore, network, storage, and console acceptance. GPU passthrough and application-specific anti-cheat or DRM behavior are separate compatibility questions and are never implied by base guest support.

## macOS guests

macOS guests are unsupported in the current Bedrock release. Bedrock does not provide macOS images, recovery downloads, device identities, firmware data, license keys, or instructions for bypassing Apple's checks.

Bedrock must reject or clearly block a macOS guest on non-Apple hardware. Apple's current macOS Tahoe 26 license is for Apple-branded systems, and its virtualization permission is conditional and purpose-limited; the license supplied with the user's exact macOS version and acquisition method controls. See Apple's [current software license agreements](https://www.apple.com/legal/sla/) and [macOS Tahoe 26 agreement](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf). This is product compatibility guidance, not legal advice.

Apple silicon is not a Bedrock host target because the current OS image and KVM machine definition are x86-64. An Intel Mac is Apple-branded hardware, but replacing macOS with Bedrock does not automatically satisfy license language that may require the Apple-branded computer to already be running the Apple software. Bedrock therefore makes no macOS-guest support claim on Intel Macs either. Any future support decision requires legal review, an Apple-hardware-only gate, user-supplied lawful installation media, a compatible machine model, and physical acceptance evidence.

## UI rules

- Show Windows driver media as user-supplied third-party software with its source and checksum; never call it a Bedrock driver.
- Do not offer Windows 11 as “supported” until the TPM and acceptance gates above pass.
- Show macOS as unsupported, not merely “advanced,” on every host.
- On non-Apple hardware, do not offer a macOS creation path.
- Never imply that GPU passthrough makes an otherwise unsupported guest supported.
