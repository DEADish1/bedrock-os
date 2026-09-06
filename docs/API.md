# Bedrock local management API

Bedrock exposes a versioned, authenticated management API only through the local Unix socket `/run/bedrock-api/api.sock`. The service does not bind a TCP port. A future web gateway may access the socket after it authenticates the browser session and applies its own authorization policy.

## Authentication

Create a client token as root with `create-api-token NAME`. The command displays the 64-character bearer token once. Bedrock stores only its SHA-256 digest in `/var/lib/bedrock/api/tokens.json`; the state is bounded to 16 uniquely named tokens and is readable only by root and the API service account.

Use `manage-api-tokens list` to inspect token names, creation times, and revocation status without exposing hashes. Use `manage-api-tokens revoke NAME` to atomically invalidate a token. Revocation takes effect on the next request and cannot be silently repeated.

Send the token as `Authorization: Bearer TOKEN`. Missing, malformed, unknown, or revoked credentials receive `401`. API responses must not be cached.

## Version 1 foundation

- `GET /api/v1/health` reports API availability.
- `GET /api/v1/dashboard` returns privacy-safe hardware, storage, alert, VM, and update summaries. Each component has an independent availability state, so stale or malformed subsystem data cannot suppress healthy telemetry from the others.
- `GET /api/v1/virtualization/capabilities` returns the existing fail-closed virtualization capability report, or `503` while that report is unavailable.
- `GET /api/v1/tasks` returns at most 256 bounded task records with monotonic timestamps and validated progress. It excludes command arguments, paths, user labels, and error text.
- `GET /api/v1/alerts` returns active alert identity, kind, severity, and timestamps without exposing device paths or other resource identifiers.
- `GET /api/v1/audit` returns the newest 100 events from a bounded append-only feed. Events expose only a stable identity, category, action, outcome, and timestamp.

Malformed, oversized, indirect, or unavailable task, alert, and audit sources fail independently with `503`; the API never returns partially validated records.

Privileged operations publish state through `record-api-task`. The writer serializes updates, rejects identity, timestamp, or progress regression, caps retained tasks at 256, and emits one privacy-bounded audit event when a task reaches a terminal state. Operations may expose stable task identity and kind, counters, and timestamps only; paths, command arguments, user labels, and raw error messages are prohibited.

All other paths return `404`. Mutating requests are deliberately disabled in this foundation and return `405` after authentication. Later mutation endpoints must delegate to the existing guarded Bedrock helpers so their independent precondition checks, exact confirmations, serialization, rollback, and audit boundaries remain authoritative.
