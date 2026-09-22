# Management task and audit coverage audit

Audit date: 2026-09-22. Scope: the 33 mutating method/path combinations in the packaged v1 OpenAPI contract. This is a source-level inventory, not release-candidate acceptance evidence. A helper mentioning `record-api-task` does not by itself prove all success, failure, interruption, and replay branches emit correct terminal records.

| Mutation family | Current task/audit path | Remaining verification |
| --- | --- | --- |
| Settings update policy | Root action broker invokes `record-api-task` | Replay, broker crash, and persisted outcome tests |
| Settings relay configure/disable | `configure-remote-relay` invokes `record-api-task` | Candidate-image restart failure and rollback |
| Remote trust changes and pairing approval | `change-remote-device` and `approve-remote-pairing` invoke `record-api-task` | Revocation, rejection, and client-visible privacy checks |
| Applications | `change-app` invokes `record-api-task` | Install, power, update, delete, and failure/restart paths |
| Backups | `change-backup` invokes `record-api-task` | Long-running progress, interrupted backup, restore drill |
| Image import/convert | `import-uploaded-vm-image` and image conversion helper invoke `record-api-task` | Large-image, conversion failure, cleanup, and replay |
| Image upload/discard | **Gap:** Unix API calls `stage_image_upload` and `discard_image_upload` directly, without task/audit recording | Add bounded, privacy-safe progress and terminal outcomes without recording image bytes or paths |
| Storage | `change-storage` delegates to `bedrock-storage`, which records bounded task stages | Each destructive operation, reboot, and media failure |
| NAS identity | `change-nas-identity` invokes `record-api-task` | Credential rotation failures and secret-free audit |
| VM lifecycle, resources, images, networks, snapshots, passthrough | Guarded VM helpers invoke `record-api-task`; passthrough failure paths were recently extended | Per-action failure, interruption, reboot, and replay matrix |
| VM console sessions | Ephemeral one-time session operation; no task record | Decide whether security audit is required; verify expiry and no token disclosure under 0.6.6 |

The pairing request/redeem manager is outside the administrator v1 mutation inventory and currently has no task record. Its security-event policy needs explicit review under 0.7.1, without exposing pairing secrets or allowing the audit stream to distinguish bad codes.

## Image upload implementation constraint

`bedrock-api` streams up to 4 TiB into a temporary file and performs the final atomic rename. It runs unprivileged, whereas `record-api-task` explicitly requires root outside test mode. The API therefore must not write the task/audit files directly or relax their ownership. A narrow broker transition for image upload/discard tasks validates UUIDs, state, and bounded progress before invoking the root task writer; it deliberately bypasses the one-shot action ledger. Upload emits queued, bounded running (at most roughly 100 updates), and terminal outcomes; discard emits queued and terminal outcomes. Unix-socket tests exercise interrupted-stream cleanup/failure audit and fail-closed upload when the broker is unavailable; [Linux validation](https://github.com/DEADish1/bedrock-os/actions/runs/35732233548) passed. Process-restart recovery and real service-UID acceptance remain unverified. Task metadata must exclude file contents, filesystem paths, bearer tokens, and pairing secrets.

The API now holds an exclusive instance lock before replacing its Unix socket. This prevents a second instance from treating an active upload as stale during future startup reconciliation. It does **not** yet reconcile interrupted task records or remove stale upload locks after a crash; those are separate acceptance work.

## Closure criteria for 0.6.3

- [ ] Add bounded task/audit coverage to direct image upload and discard operations, including failure and interrupted-stream outcomes.
- [ ] Test every family above against the real broker and Unix API, not just source presence or a mocked browser backend.
- [ ] Verify terminal state after restart/crash recovery, idempotent replay, denied request, and partial failure where applicable.
- [ ] Review privacy of task/audit fields, retention bounds, and pairing/console security events on the candidate image.
