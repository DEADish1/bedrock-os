# Installer disposable-drive acceptance

This procedure is destructive and must be run only on a disposable removable drive containing no needed data. It is not part of automated CI, and fixture results cannot satisfy the physical-device release gate.

The Linux acceptance runner requires root authority, a fresh inventory from the packaged Linux scanner, an unmounted writable removable whole disk, the exact target ID/path/capacity, the complete erase phrase, and this opt-in sentence:

`I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE`

Drives larger than 256 GiB require the additional sentence `I CONFIRM THIS LARGE DRIVE IS DISPOSABLE`. This conservative ceiling reduces the chance of selecting a large internal or backup disk.

The runner writes through the existing guarded command-line writer, synchronizes the media, rereads the complete signed range, and emits a privacy-safe write report without serial numbers. That initial report deliberately records `boot_completed_at: null`, `booted_from_media: false`, and `guided_installer_opened: false`, so it cannot pass physical acceptance before a real boot.

Safely eject the disposable drive, boot it on supported UEFI hardware, and confirm that the Bedrock guided installer opens without a terminal. Only after directly observing both results, create the completed report with the actual UTC observation time:

```sh
jq --arg completed "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  '.boot_completed_at = $completed |
   .checks.booted_from_media = true |
   .checks.guided_installer_opened = true' \
  disposable-usb-write.json > disposable-usb-complete.json
```

The shared validator recognizes exact Linux `/dev` whole devices, macOS whole `diskN` devices, and Windows `PhysicalDriveN` identities. Validate the completed real evidence with:

```sh
sh installer/acceptance/validate-real-device-report.sh path/to/report.json
```

Fixture reports require an explicit validator test switch and are rejected by the normal physical-report validator.

The report validator also rejects write-only or unbooted media, indirect or oversized files, unknown fields, private identifiers, noncanonical timestamps, and partition paths presented as Linux whole disks. Use `docs/ACCEPTANCE-0.2-0.3.md` to bind the passing report to the same image used for the final boot and installed-system evidence.

Windows and macOS now have matching native preflight gates. Each uses its packaged scanner, accepts only one safe removable whole-device identity, requires the same destructive and large-drive attestations, rechecks the exact path/capacity/erase phrase, and emits a plan with `ready_for_writer: false`. Their fixture tests run on matching Windows and macOS GitHub hosts. These gates deliberately do not write; the production desktop helper connection and genuine disposable-drive reports on all supported platforms remain required before v0.3 media writing can be marked complete.
