# Administrator guide

Bedrock is administered from the authenticated local interface and, while interface work remains incomplete, from its narrow root-only commands. Do not expose the API Unix socket or VM console sockets directly to a network. Keep a verified backup and configuration export before storage, update, or recovery work.

## Routine checks

Review dashboard health, active alerts, task progress, and audit history. Investigate `limited` hardware visibility instead of treating it as healthy. Check backup snapshot history and periodically verify restored contents. Apply signed Bedrock updates only after reading their release notes; the automatic setting checks availability but does not install.

Use `bedrock-storage-guided` for storage creation and recovery, `bedrock-nas` for datasets and shares, `bedrock-apps` for isolated services, `bedrock-backup` for encrypted backups, and `bedrock-update-settings` for update-check preferences. Each destructive or trust-changing operation requires its command-specific exact confirmation. Never bypass a rejected plan by editing state files.

## Planned maintenance

Run `bedrock-maintenance enter "ENTER BEDROCK MAINTENANCE"`. Confirm managed VMs and applications stop, shares and scheduled writers quiesce, and the state reports `active` before servicing storage or power. When finished, run `bedrock-maintenance exit "EXIT BEDROCK MAINTENANCE"`; it restores only workloads and units recorded as active on entry.

## Accounts, devices, and secrets

Use a distinct administrator account and revoke unused API or remote-device credentials promptly. Credentials, recovery codes, signing keys, backup passwords, and notification secrets do not belong in issue reports or configuration archives. After bare-metal recovery, rotate excluded credentials rather than copying old secret state.

## Evidence and support

Record the exact Bedrock version and image SHA-256 before testing. Preserve release manifests, checksums, acceptance reports, and recovery-drill reports. Follow the [troubleshooting guide](TROUBLESHOOTING.md) before creating a privacy-reviewed [diagnostic bundle](DIAGNOSTICS.md).
