# Remote pairing gateway

Bedrock keeps unauthenticated pairing bootstrap separate from the authenticated administrator API. `bedrock-pairing-gateway` listens only on `/run/bedrock-pairing/gateway.sock`; it never opens a TCP or UDP port. The socket is available only to the dedicated `bedrock-remote` transport identity. A future Noise/relay ingress process must forward only the two bounded messages below and must not expose the socket or the local management API directly.

The gateway accepts one JSON object of at most 1,024 bytes per connection and returns one bounded JSON object. New requests are globally limited to 30 per minute and all messages to 120 per minute before the pairing manager runs. Every failure has the same `pairing-request-rejected` response so a remote caller cannot distinguish unknown, unapproved, expired, used, wrong-code, or wrong-key state.

## Request pairing

Send `{"schema":1,"action":"request","client_public_key":"HEX_X25519_PUBLIC_KEY"}`. A successful response contains the pairing UUID, ten-minute expiry, server public-key fingerprint, manual code, and equivalent versioned QR payload. The raw pending client key and manual code are never stored; only their SHA-256 values are persisted.

The client must display the server fingerprint and manual code for comparison. The administrator then reviews the key-free pending request in the authenticated local interface and types its exact approval phrase. The gateway has no approval operation.

## Redeem approval

Send `{"schema":1,"action":"redeem","pairing_id":"UUID","manual_code":"BRK-XXXX-XXXX","client_public_key":"SAME_HEX_KEY"}`. Redemption succeeds only when the request is approved, unexpired, from the current boot, below the attempt cap, unused, and bound to the same client key. The state update registers a distinct device and marks the request used under one exclusive lock; replay fails.

## Server identity

`bedrock-remote-identity.service` creates the server X25519 private key from OpenSSL's operating-system random source with owner-only permissions and derives the public identity used for pairing fingerprints. Initialization is idempotent, verifies that the files match, and recovers a missing public file from the private key after interruption. It never replaces an existing private identity automatically.

This gateway completes the server-side bootstrap boundary only. Remote transport still must implement the approved Noise protocol, bind the redeemed device key into its transcript and service target, enforce revocation on every session, and pass the full transport acceptance matrix before pairing can be marked complete.
