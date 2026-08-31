# Virtual machine and image-library acceptance

Milestone 0.5 closes only after one exact Bedrock OS image passes separate Linux and Windows guest sessions on KVM. Unit fixtures and a successful image build are necessary but do not replace these sessions.

Use disposable guests named `acceptance-linux` and `acceptance-windows`, lawful user-supplied installation media, and no personal accounts or production data. Copy `os/tests/vm-guest-acceptance.example.json` once for each role, change `mode` to `physical`, use distinct version-4 session UUIDs, record the exact Bedrock and guest-media SHA-256 values, and retain only the bounded observations in the schema.

Each guest must demonstrate:

- accelerated x86-64 execution with the managed UEFI Secure Boot and persistent TPM 2.0 definition;
- completed installation, the assigned CPU and memory, VirtIO storage/network, guest-agent readiness, and the browser console;
- data persistence across a guest reboot and a Bedrock host reboot;
- an offline snapshot, a deliberate disposable-file mutation, snapshot restoration, and restoration of the baseline file SHA-256.

The report deliberately excludes guest addresses, credentials, hostnames, serial numbers, free-form notes, and guest content. Review it before archival. Validate the pair with:

```sh
sh os/tests/validate-vm-guest-acceptance.sh BEDROCK_IMAGE_SHA256 linux.json windows.json
```

Windows remains `blocked-pending-acceptance` until this physical-mode pair passes. GPU/USB passthrough is independently hardware-specific and is not required to establish base Windows or Linux guest support.
