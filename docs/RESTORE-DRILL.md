# Full restore drill

The roadmap restore item closes only after one controlled acceptance run proves recovery of ordinary files, VM data, Bedrock configuration, and a server whose system drive has failed. Use expendable test data and a replacement system drive. Do not simulate the failed-system-drive scenario by overwriting the original drive.

Record SHA-256 hashes before backup and after restore. Confirm that file restore refuses an existing destination, the restored VM disk matches its baseline and boots, an offline VM snapshot restores correctly, restored configuration survives reboot, the pre-restore recovery copy is retained, and excluded API/remote credentials are rotated.

For the system-drive scenario, remove or disconnect the original system drive, perform a clean install to a different drive, import the existing data pool without creating a pool or filesystem, restore configuration, reboot, and verify shares and managed guests. Preserve the original drive until the complete drill passes.

Copy `os/tests/restore-drill-report.example.json`, replace every example value with observed evidence, and validate it with:

```sh
os/tests/validate-restore-drill-report.sh restore-drill-report.json
```

The validator deliberately requires every scenario to pass and matching content hashes. Keep the completed report with the release evidence; do not commit host identifiers, usernames, secrets, filenames, or private storage paths.
