# Remote relay connector

Bedrock's relay connector makes only outbound TCP connections. It never creates an inbound TCP or UDP listener, never changes the router, and remains disabled unless both `/var/lib/bedrock/remote/relay.json` and `/var/lib/bedrock/remote/relay-token` have been deliberately provisioned. The service runs as `bedrock-remote` with no capabilities and receives those root-owned files through systemd credentials.

The outer connection requires exactly TLS 1.3, normal platform certificate and hostname verification, and ALPN `bedrock-relay/1`. Python's TLS client sends no early data, so registration and opaque Noise bytes are never sent as TLS 0-RTT. A failed connection backs off to 30 seconds and reconnects without logging credentials, routes, payloads, or remote addresses.

## Relay framing

Every relay frame has a fixed network-order header: schema version byte, message-type byte, 16-byte stream identifier, 32-bit payload length, then at most 65,536 payload bytes. Registration, registered, ping, and pong use the all-zero stream identifier. Open, data, and close require a nonzero identifier. Unknown versions, types, stream transitions, duplicate opens, empty data, oversized payloads, or more than 16 concurrent streams close the relay connection.

Registration contains only schema version, the server's opaque routing UUID, and its relay authorization credential inside TLS. An open contains a canonical random session UUID plus either pairing mode or an opaque device UUID. Data payloads are passed unchanged and are Noise handshake messages or ciphertext; the connector does not interpret them. The relay can observe routing IDs, timing, and sizes but receives no server name, device label, API path, management content, Noise key, pairing code, or local API bearer token.

For every open, the connector creates a local Unix socket pair and passes one connected descriptor to the kernel-peer-authenticated [remote stream broker](REMOTE-PAIRING-GATEWAY.md#connected-stream-launch-boundary). Pairing and authenticated sessions therefore retain their separate credentials, time limits, revocation ownership, and API boundaries. Relay connection loss closes all local streams; clients reconnect with a fresh Noise handshake.

`/usr/share/bedrock/remote/relay-config.example.json` documents the strict configuration fields. The production relay endpoint and authorization credential are deployment inputs, not source-controlled defaults. The root-only `configure-remote-relay` boundary accepts one non-symlink request file, requires an exact endpoint-and-route confirmation, writes only the nonsecret fields to `relay.json`, isolates the token in its own owner-only file, and starts the connector. Disablement stops the connector before permanently removing both files and requires the exact `DISABLE REMOTE RELAY` confirmation. Callers must stage the configure request in a root-only temporary location and delete it immediately after completion because it contains the token.

End-to-end acceptance still requires a production endpoint plus a production client; the repository test uses a temporary local CA, requires TLS 1.3 and the exact ALPN, validates registration and routing, and proves opaque bytes traverse the descriptor handoff unchanged.
