# Bedrock local management API

Bedrock exposes a versioned, authenticated management API only through the local Unix socket `/run/bedrock-api/api.sock`. The service does not bind a TCP port. A future web gateway may access the socket after it authenticates the browser session and applies its own authorization policy.

## Authentication

Create a client token as root with `create-api-token NAME`. The command displays the 64-character bearer token once. Bedrock stores only its SHA-256 digest in `/var/lib/bedrock/api/tokens.json`; the state is bounded to 16 uniquely named tokens and is readable only by root and the API service account.

Send the token as `Authorization: Bearer TOKEN`. Missing, malformed, unknown, or revoked credentials receive `401`. API responses must not be cached.

## Version 1 foundation

- `GET /api/v1/health` reports API availability.
- `GET /api/v1/virtualization/capabilities` returns the existing fail-closed virtualization capability report, or `503` while that report is unavailable.

All other paths return `404`. Mutating requests are deliberately disabled in this foundation and return `405` after authentication. Later mutation endpoints must delegate to the existing guarded Bedrock helpers so their independent precondition checks, exact confirmations, serialization, rollback, and audit boundaries remain authoritative.
