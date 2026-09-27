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
| Image upload/discard | Unix API records bounded progress and terminal outcomes through the root broker | Discard crash recovery, candidate consistency, and actual service-UID acceptance |
| Storage | `change-storage` delegates to `bedrock-storage`, which records bounded task stages | Each destructive operation, reboot, and media failure |
| NAS identity | `change-nas-identity` invokes `record-api-task` | Credential rotation failures and secret-free audit |
| VM lifecycle, resources, images, networks, snapshots, passthrough | Guarded VM helpers invoke `record-api-task`; passthrough failure paths were recently extended | Per-action failure, interruption, reboot, and replay matrix |
| VM console sessions | Ephemeral one-time session operation; no task record | Decide whether security audit is required; verify expiry and no token disclosure under 0.6.6 |

The pairing request/redeem manager is outside the administrator v1 mutation inventory and currently has no task record. Its security-event policy needs explicit review under 0.7.1, without exposing pairing secrets or allowing the audit stream to distinguish bad codes.

## Image upload implementation constraint

`bedrock-api` streams up to 4 TiB into a temporary file and performs the final atomic rename. It runs unprivileged, whereas `record-api-task` explicitly requires root outside test mode. The API therefore must not write the task/audit files directly or relax their ownership. A narrow broker transition for image upload/discard tasks validates UUIDs, state, and bounded progress before invoking the root task writer; it deliberately bypasses the one-shot action ledger. Upload emits queued, bounded running (at most roughly 100 updates), and terminal outcomes; discard emits queued and terminal outcomes. Unix-socket tests exercise interrupted-stream cleanup/failure audit and fail-closed upload when the broker is unavailable; [Linux validation](https://github.com/DEADish1/bedrock-os/actions/runs/35732233548) passed. Process-restart recovery and real service-UID acceptance remain unverified. Task metadata must exclude file contents, filesystem paths, bearer tokens, and pairing secrets.

The API holds an exclusive instance lock before replacing its Unix socket. On startup, it marks queued/running image-upload tasks failed through the broker, then removes stale upload temporary files, orphaned data without metadata, and upload locks. A test seeds a queued task plus orphaned files, restarts the API, and checks terminal audit and cleanup while preserving a complete candidate with metadata. Linux validation and real service-UID acceptance remain pending. Discard recovery, broker downtime during reconciliation, and candidate metadata consistency after a crash still require review.

The bounded task writer now retains queued/running tasks ahead of older terminal records, so unrelated completed activity cannot evict the only state needed to reconcile an in-flight operation. It rejects a 257th active task rather than silently losing one. Linux validation of this retention change remains pending.

## Closure criteria for active checklist 0.6.2 and 0.6.6

Discard recovery now publishes a complete, fsynced intent by exclusively hard-linking it to the existing import-lock path. Empty import-owned locks remain untouched. The intent binds the requested hash, candidate type/size/inode, and task identity; recovery validates candidate state before removing the manifest and data, synchronizes each removal, and records the terminal outcome before releasing the lock. Interrupted pre-publication tasks fail without deleting the candidate. Tests terminate before publication and after each directory-sync phase, then check recovery, unchanged import fixtures, and one terminal audit event across repeated recovery. Upload publication now synchronizes data and metadata directory entries; rejected uploads only clean up data they created. These new tests await Linux validation; legacy discard tombstones, real service-UID boundaries, and physical power-loss acceptance remain open.

The broker-outage and import-preservation restart tests passed [run 36301732521 at bc2d7db](https://github.com/DEADish1/bedrock-os/actions/runs/36301732521), including validation, both builds, and reproducibility; physical acceptance was skipped.

The discard interruption/replay tests above passed Linux validation in [run 36322568933 at e0d0db5](https://github.com/DEADish1/bedrock-os/actions/runs/36322568933) on 2026-09-27. This supersedes their pending-validation note; image builds and reproducibility were still running when recorded. The API/broker tests use test-mode credentials and do not close the actual service-UID boundary or physical acceptance gates.

2026-09-27 evidence update: [run 36270106308 at a668825](https://github.com/DEADish1/bedrock-os/actions/runs/36270106308) passed Linux validation, both image builds, and reproducibility. This supersedes the pending Linux-validation notes below for task retention, symlink rejection, transaction replay, startup recovery, simulated ENOSPC, and audit retention. Physical acceptance was skipped; real service-UID and physical power-loss acceptance remain open. Additional API restart tests now assert that an unavailable broker leaves staged files and task/audit bytes unchanged, and that recovery preserves import-owned locks/data; validation of these newest tests is pending.

Startup integration: `bedrock-action-broker.service` runs `record-api-task --recover` as a root pre-start step. Recovery uses the same exclusive lock as normal writes and creates no synthetic task. Tests cover all three interrupted write stages and an unchanged second recovery invocation. Linux validation and actual systemd/service-UID acceptance are still required.

The transaction implementation passed [Linux validation at be459a3](https://github.com/DEADish1/bedrock-os/actions/runs/36269908331). Additional tests inject `ENOSPC` during journal, audit, and task writes, then verify unchanged prior task state, removal of temporary files, successful recovery/retry, and one terminal audit event. These simulate write failures; they do not substitute for physical power-loss or filesystem qualification. Validation of these additional tests is pending.

2026-09-26 review: the task writer rejects dangling state/audit symlinks and indirect lock files, and synchronizes the parent directory after replacing task state. Tests verify rejected links do not create targets or alter a lock target's permissions. A root-only durable transaction now saves the intended task snapshot and bounded audit content before publishing either, then replays under the task lock on the next writer invocation. Atomic audit replacement avoids partial appended lines. Tests terminate after journal, audit and task publication, then verify recovery and duplicate-free replay; Linux validation of the transaction change is pending. Startup recovery integration, disk-full behavior, audit retention, and remaining staging cases still gate checklist item 0.6.2.

- [ ] Add bounded task/audit coverage to direct image upload and discard operations, including failure and interrupted-stream outcomes.
- [ ] Test every family above against the real broker and Unix API, not just source presence or a mocked browser backend.
- [ ] Verify terminal state after restart/crash recovery, idempotent replay, denied request, and partial failure where applicable.
- [ ] Review privacy of task/audit fields, retention bounds, and pairing/console security events on the candidate image.
