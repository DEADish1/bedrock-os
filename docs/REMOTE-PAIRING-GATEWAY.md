# Remote pairing gateway

Bedrock keeps unauthenticated pairing bootstrap separate from the authenticated administrator API. `bedrock-pairing-gateway` listens only on `/run/bedrock-pairing/gateway.sock`; it never opens a TCP or UDP port. The socket is available only to the dedicated `bedrock-remote` transport identity. `bedrock-noise-transport` is the connected-stream responder used by future direct or relay ingress; it is deliberately not a network listener and cannot expose the gateway or local management API directly.

The responder uses Debian's maintained `python3-noiseprotocol` implementation of `Noise_XX_25519_ChaChaPoly_SHA256`, loads the existing server PKCS#8 X25519 identity, fixes a versioned Bedrock prologue, and completes mutual static-key authentication. Each record has a fixed header containing protocol version, the handshake-derived session identifier, direction, 64-bit sequence, message type, and plaintext length. That complete header is Noise AEAD associated data. Unknown versions or types, wrong sessions or directions, nonconsecutive sequences, malformed lengths, ciphertext changes, truncated handshakes, and messages above the bound fail closed. The client public key sent to the gateway is always taken from the completed Noise transcript, never trusted from JSON.

The gateway accepts one JSON object of at most 1,024 bytes per connection and returns one bounded JSON object. New requests are globally limited to 30 per minute and all messages to 120 per minute before the pairing manager runs. Every failure has the same `pairing-request-rejected` response so a remote caller cannot distinguish unknown, unapproved, expired, used, wrong-code, or wrong-key state.

## Request pairing

Send `{"schema":1,"action":"request","client_public_key":"HEX_X25519_PUBLIC_KEY"}`. A successful response contains the pairing UUID, ten-minute expiry, server public-key fingerprint, manual code, and equivalent versioned QR payload. The raw pending client key and manual code are never stored; only their SHA-256 values are persisted.

The client must display the server fingerprint and manual code for comparison. The administrator then reviews the key-free pending request in the authenticated local interface and types its exact approval phrase. The gateway has no approval operation.

## Redeem approval

Send `{"schema":1,"action":"redeem","pairing_id":"UUID","manual_code":"BRK-XXXX-XXXX","client_public_key":"SAME_HEX_KEY"}`. Redemption succeeds only when the request is approved, unexpired, from the current boot, below the attempt cap, unused, and bound to the same client key. The state update registers a distinct device and marks the request used under one exclusive lock; replay fails.

## Authorize a device session

Send `{"schema":1,"action":"authorize","device_id":"UUID","client_public_key":"SAME_HEX_KEY"}` only after the Noise handshake proves possession of the matching private key. Authorization requires the exact registered public key, rejects expired or revoked devices, records the last-seen time, and starts only that device's `bedrock-remote-device@DEVICE.target`. The transport service must join that target so revocation terminates its live sessions.

## Server identity

`bedrock-remote-identity.service` creates the server X25519 private key from OpenSSL's operating-system random source with owner-only permissions and derives the public identity used for pairing fingerprints. Initialization is idempotent, verifies that the files match, and recovers a missing public file from the private key after interruption. It never replaces an existing private identity automatically.

The server-side Noise control transport now proves client-key possession before request, redemption, or authorization reaches the gateway. An authorized stream is launched as a uniquely named transient service with `PartOf=bedrock-remote-device@DEVICE.target`; the transport also requires its first authenticated action to name that same device. The private server key stays root-only and reaches the unprivileged, network-isolated service through a systemd credential. Stopping the device target therefore synchronously terminates every such stream.

After authorization, the stream accepts bounded, sequential encrypted API records until the one-hour, 1 GiB-per-direction, or record-count limit is reached. The launcher creates a unique short-lived API bearer token, supplies it to the service as a second credential, and revokes and deletes it when the service exits. The remote client never receives or supplies this bearer token. Only `/api/v1/` requests, four methods, four bounded non-authorization headers, and bodies within the Noise record limit are forwarded to the existing Unix API; status, content type, ETag, and bounded body are returned inside the encrypted response. Cipher states rekey together at the fixed record interval. Relay/direct ingress and independent cryptographic review remain required before pairing can be marked complete.

## Connected-stream launch boundary

The unprivileged relay connector does not receive permission to start services or read either credential. It passes one already-connected local stream descriptor plus a bounded pairing or device route over `/run/bedrock-remote-launch/launch.sock`. The root broker authenticates the connector through kernel peer credentials on an AF_UNIX `SOCK_SEQPACKET` socket, accepts exactly one connected AF_UNIX stream descriptor, validates canonical session and device UUIDs, caps concurrent children at 16, and launches only the fixed pairing or device helper. It never reads bytes from the forwarded stream. Pairing sessions have a 30-second lifetime and no API group or credential; device sessions retain the stricter device-target and temporary-API-token boundary above.
