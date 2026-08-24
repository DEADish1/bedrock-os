# Installer disposable-drive acceptance

This procedure is destructive and must be run only on a disposable removable drive containing no needed data. It is not part of automated CI, and fixture results cannot satisfy the physical-device release gate.

The first acceptance runner supports Linux. It requires root authority, a fresh inventory from the packaged Linux scanner, an unmounted writable removable whole disk, the exact target ID/path/capacity, the complete erase phrase, and this opt-in sentence:

`I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE`

Drives larger than 256 GiB require the additional sentence `I CONFIRM THIS LARGE DRIVE IS DISPOSABLE`. This conservative ceiling reduces the chance of selecting a large internal or backup disk.

The runner writes through the existing guarded command-line writer, synchronizes the media, rereads the complete signed range, and emits a privacy-safe JSON report without serial numbers. Validate real evidence with:

```sh
sh installer/acceptance/validate-real-device-report.sh path/to/report.json
```

Fixture reports require an explicit validator test switch and are rejected by the normal physical-report validator. Windows and macOS physical acceptance, plus the desktop helper’s production pipeline connection, remain required before v0.3 media writing can be marked complete.
