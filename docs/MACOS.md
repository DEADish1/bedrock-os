# macOS guidance

The Bedrock desktop installer target is macOS 13 or newer on supported Macs. A release build must be universal for Intel and Apple silicon, signed with the project's Apple Developer ID, use its fixed privileged-helper identity, and be notarized and stapled. Unsigned preview builds are for development only and must not ask users to bypass Gatekeeper or weaken system security.

The installer may write only a freshly enumerated removable whole device after signature and checksum verification, exact erase confirmation, administrator authorization, cache synchronization, and safe-eject handling. It must never write the Mac's system disk. Final hardware acceptance requires a genuine disposable-drive report from macOS.

Apple silicon cannot run the current amd64 Bedrock server image as a supported physical host. macOS is also not a supported Bedrock guest. Bedrock distributes no Apple installation media, device identity, firmware, license key, or bypass instructions. The license supplied with the user's exact Apple software controls; see [guest compatibility](GUEST-COMPATIBILITY.md).
