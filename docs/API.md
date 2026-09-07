# Bedrock local management API

Bedrock exposes a versioned, authenticated management API only through the local Unix socket `/run/bedrock-api/api.sock`. The service does not bind a TCP port. A future web gateway may access the socket after it authenticates the browser session and applies its own authorization policy.

## Authentication

Create a client token as root with `create-api-token NAME`. The command displays the 64-character bearer token once. Bedrock stores only its SHA-256 digest in `/var/lib/bedrock/api/tokens.json`; the state is bounded to 16 uniquely named tokens and is readable only by root and the API service account.

Use `manage-api-tokens list` to inspect token names, creation times, and revocation status without exposing hashes. Use `manage-api-tokens revoke NAME` to atomically invalidate a token. Revocation takes effect on the next request and cannot be silently repeated.

Send the token as `Authorization: Bearer TOKEN`. Missing, malformed, unknown, or revoked credentials receive `401`. API responses must not be cached.

## Version 1 foundation

- `GET /api/v1/health` reports API availability.
- `GET /api/v1/openapi.json` returns the authenticated OpenAPI 3.1 contract for every implemented v1 route.
- `GET /api/v1/dashboard` returns privacy-safe hardware, storage, alert, VM, and update summaries. Each component has an independent availability state, so stale or malformed subsystem data cannot suppress healthy telemetry from the others.
- `GET /api/v1/virtualization/capabilities` returns the existing fail-closed virtualization capability report, or `503` while that report is unavailable.
- `GET /api/v1/tasks` returns at most 256 bounded task records with monotonic timestamps and validated progress. It excludes command arguments, paths, user labels, and error text.
- `GET /api/v1/alerts` returns active alert identity, kind, severity, and timestamps without exposing device paths or other resource identifiers.
- `GET /api/v1/audit` returns the newest 100 events from a bounded append-only feed. Events expose only a stable identity, category, action, outcome, and timestamp.
- `GET /api/v1/remote/devices` returns names, lifecycle timestamps, and revoked/expired state from a root-generated privacy-safe view. Public keys and fingerprints remain inaccessible to the API service.
- `GET /api/v1/apps` returns configured application identity, networking mode, resource limits, update policy, and creation time from a root-generated privacy-safe view. Registry locations and image digests remain inaccessible to the API service.
- `GET /api/v1/backups` returns plan identity, schedule, retention, last-success time, and snapshot availability from a root-generated privacy-safe view. Source paths, repository locations, credentials, and snapshot identifiers remain inaccessible to the API service.
- `GET /api/v1/hardware` returns processor, memory, disk capability, storage-controller, network-link, GPU, and USB-count data while omitting device paths, interface names, MAC addresses, PCI/USB topology, numeric vendor/device IDs, serials, and IOMMU membership.
- `GET /api/v1/vms` returns the bounded managed VM inventory with lifecycle state, autostart, assigned CPU and memory, snapshot count, and logical image/network attachment names. It does not expose disk paths, console sockets, MAC addresses, libvirt XML, or host device topology.
- `GET /api/v1/images` returns the verified image name, format, byte size, SHA-256, and conversion provenance flag from a root-generated path-free view. Managed filesystem locations remain inaccessible to the API service.
- `GET /api/v1/storage` returns disk capacity and SMART summaries, Linux RAID and ZFS health and rebuild progress, and bounded hardware-RAID visibility counts. Device paths, serial numbers, member patterns, controller addresses, slot identifiers, and vendor descriptions remain inaccessible to clients.
- `GET /api/v1/settings` returns the validated update-check choice and release channel plus the enforced no-automatic-install and telemetry-disabled states. Hostname, account, network, credential, and other first-run configuration remain inaccessible to clients.
- `GET /api/v1/users` returns managed NAS account names, credential-rotation generation/timestamps, and group names with member counts. Passwords, hashes, member identities, datasets, ACLs, share paths, and snapshot names remain inaccessible to clients.

Malformed, oversized, indirect, or unavailable task, alert, audit, remote-device, application, backup, hardware, VM, image, storage, settings, and user sources fail independently with `503`; the API never returns partially validated records.

Privileged operations publish state through `record-api-task`. The writer serializes updates, rejects identity, timestamp, or progress regression, caps retained tasks at 256, and emits one privacy-bounded audit event when a task reaches a terminal state. Operations may expose stable task identity and kind, counters, and timestamps only; paths, command arguments, user labels, and raw error messages are prohibited.

Verified update downloads publish queued, byte-accurate running, succeeded, and failed states. Resumed bytes count only after the complete artifact passes size and SHA-256 verification, and the final success state is emitted only after the whole signed bundle passes verification.

VM start, stop, force-stop, and restart publish three bounded steps: managed-state and libvirt preconditions verified, the requested command issued, and the expected final power state observed. Task and audit records identify only the action; VM names remain outside the feed.

Storage create, expand, scrub, replace, export, and import operations publish three bounded steps: managed-state and safety preconditions verified, the backend operation completed, and durable state plus the existing storage audit committed. Task records identify only the operation kind; pool names and device paths remain private.

All other paths return `404`. Mutating requests are deliberately disabled in this foundation and return `405` after authentication. Later mutation endpoints must delegate to the existing guarded Bedrock helpers so their independent precondition checks, exact confirmations, serialization, rollback, and audit boundaries remain authoritative.

The first mutation-side privilege boundary is now packaged separately from the API. A root action broker listens only on `/run/bedrock-action-broker/action.sock`, authenticates the kernel-reported peer as the `bedrock-api` account, accepts a strict bounded schema, and maps update-policy choices to fixed arguments for `bedrock-update-settings` without invoking a shell. Successful request UUIDs and request hashes are retained in a bounded owner-only ledger so identical retries are safe and conflicting reuse fails closed. The broker never returns helper output. No public mutating API route is enabled until its authenticated authorization, conflict, response-schema, and end-to-end tests are added.

The packaged schema is the machine-readable source of truth for interface clients. API tests require its route set and bearer security declaration to match the implementation; undocumented routes and unauthenticated schema discovery are rejected.
