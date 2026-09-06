# Remote access transport and threat model

Status: approved design contract; implementation and independent review remain release gates.

## Security objective

Bedrock remote access provides mutually authenticated end-to-end encryption between one approved client device and one server. A discovery or relay service may route opaque records, but it cannot decrypt management requests, responses, console traffic, credentials, or device keys. Local API authorization remains authoritative after transport authentication.

The design uses the fundamental Noise XX handshake as `Noise_XX_25519_ChaChaPoly_SHA256`. XX is appropriate before a client knows the server static key; both static identities become authenticated during the handshake. The protocol name and state machine follow the [Noise Protocol Framework revision 34](https://noiseprotocol.org/noise.html). Implementations must use a maintained, reviewed Noise library and its test vectors; Bedrock must not implement cryptographic primitives itself.

The relay-facing hop additionally requires TLS 1.3, with 0-RTT disabled, bounded records, hostname verification, and normal platform trust. TLS protects routing metadata on each hop but is not the end-to-end security boundary. TLS 1.3 is defined by [RFC 8446](https://datatracker.ietf.org/doc/html/rfc8446). Static certificate pinning is not required for the relay: OWASP cautions that pinning adds rotation risk unless a specific threat model and safe out-of-band pin lifecycle justify it. The paired Noise static key is the server identity pin.

## Identities and keys

- The server and every client generate separate X25519 static key pairs from the operating system cryptographic random source. Private keys are non-exportable where the platform keystore supports that property.
- Pairing transfers the server public-key fingerprint and one short-lived, single-use approval secret through the QR/manual-code flow. The user verifies and approves the pending device on the server console.
- A successful pairing binds one client public key to one device record. Device records are independently nameable, expirable, and revocable. Revocation is checked before every new session and terminates active sessions.
- Google OpenID Connect, if later enabled, may establish user identity for discovery but cannot approve a device, derive transport keys, decrypt traffic, or bypass the local server confirmation.
- Session keys are derived only by the Noise transcript. They are never stored. A fresh handshake is required after one hour, one GiB in either direction, or 1,048,576 encrypted records, whichever occurs first.

Client private keys must use Windows CNG/DPAPI-backed key protection or the macOS Keychain/Secure Enclave where available. This satisfies the secure-storage objective represented by [OWASP MASVS-STORAGE](https://mas.owasp.org/MASVS/). Recovery creates a new device identity; keys are never restored from ordinary backups.

## Record protocol

Every encrypted record carries a protocol version, session identifier, direction-specific monotonically increasing 64-bit sequence, message type, payload length, and ciphertext. The authenticated associated data covers all framing fields. Receivers reject replayed, skipped-beyond-window, wrong-session, unknown-type, oversized, or post-revocation records before dispatch. The maximum plaintext record is 1 MiB; console streams use smaller flow-controlled chunks.

Requests retain the local API request identifier and authorization capability. Mutations use idempotency keys and the same server-side exact-confirmation and fresh-precondition boundaries as local access. Transport authentication never turns a read capability into a mutation capability.

## Adversaries and required controls

| Adversary or failure | Required control and expected result |
| --- | --- |
| Passive network or relay observer | Sees timing, size, and endpoints but no plaintext; application data is protected by Noise transport keys. |
| Active man-in-the-middle | Cannot authenticate both paired static identities; handshake or fingerprint verification fails closed. |
| Malicious or compromised relay | Can delay, reorder, drop, or replay opaque records; sequence, session, and AEAD checks reject modification and replay. It cannot decrypt or authorize. |
| Stolen pairing code | Code alone is insufficient after expiry, first use, or denial; server-console approval and transcript-bound device key are required. |
| Stolen client device | Platform key protection and immediate server-side revocation limit use; revocation terminates live sessions and blocks new handshakes. |
| Compromised identity provider | Cannot pair, decrypt, authorize mutations, or replace server/client device keys. |
| Downgrade or cross-protocol attack | Exact protocol name, version, roles, server identifier, and pairing context are transcript-bound; unknown versions fail closed. |
| Replay after reconnect | New handshake produces a new session identifier and keys; old-session records are rejected. |
| Resource exhaustion | Handshake, connection, record-size, queue, bandwidth, and per-source attempt limits apply before expensive application work. |
| Clock error | Sequence and session security do not depend on wall-clock ordering. Expiry uses monotonic time during a running session and conservative failure after reboot. |

## Privacy and logging

The relay retains only the minimum routing identifier and short operational counters, with a documented short retention period. It must not receive server names, client labels, API paths, alert content, VM names, device serials, LAN addresses, tokens, keys, or plaintext errors. Server audit records contain stable pseudonymous device IDs, security action, outcome, and timestamp; they exclude IP addresses by default. Diagnostic export requires explicit consent and secret redaction.

## Explicit limitations

This design does not protect plaintext visible on a compromised client or server, prevent traffic analysis, guarantee relay availability, or recover an unrecoverable device key. It does not make browser delivery trustworthy on a hostile client. Remote console content remains sensitive even though encrypted.

## Verification gates

Implementation cannot ship until automated tests cover official Noise vectors, mutual authentication, transcript binding, key separation, replay/reorder/truncation, version downgrade, record limits, rekey boundaries, expiry, revocation during active traffic, relay opacity, TLS configuration, concurrent sessions, crash recovery, and secret-free logs. A third-party review must cover protocol composition, pairing, key storage, authorization, relay behavior, updates, and client signing. Findings rated critical or high block release.

The machine-readable invariant set is packaged at `/usr/share/bedrock/remote/transport-policy.json` and is validated during every image build.

## Pairing implementation status

The root-only `manage-remote-pairing` boundary implements pending-request issuance, exact server approval, and single-use redemption. It stores SHA-256 values for the manual code and client public key, never the plaintext code or raw client key. Requests expire after ten monotonic minutes, are invalidated by reboot, reject replay, and cap failed redemption attempts. The interface, relay ingress, per-device record issuance, and transport handshake remain open, so the roadmap pairing item is not yet complete.
