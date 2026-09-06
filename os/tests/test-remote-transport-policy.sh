#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
policy="$ROOT/os/config/includes.chroot/usr/share/bedrock/remote/transport-policy.json"
[ -f "$policy" ] && [ ! -L "$policy" ]
jq -e '
  (keys|sort)==(["authorization","identity","implementation","noise_protocol","outer_transport","pairing","records","rehandshake","relay","schema","status"]|sort) and
  .schema==1 and .status=="design-approved-implementation-pending" and
  .noise_protocol=="Noise_XX_25519_ChaChaPoly_SHA256" and
  .outer_transport=={minimum_tls:"1.3",zero_rtt:false,relay_is_end_to_end_trusted:false} and
  .identity.server_static_key=="x25519" and .identity.per_device_static_key=="x25519" and .identity.oidc_can_approve_devices==false and
  .pairing.server_console_approval and .pairing.single_use and .pairing.binds_server_fingerprint and (.pairing.expires_seconds<=600) and
  .records.aead_associated_framing and .records.directional_sequence_bits==64 and (.records.maximum_plaintext_bytes<=1048576) and .records.unknown_versions_fail_closed and
  (.rehandshake.maximum_age_seconds<=3600) and (.rehandshake.maximum_direction_bytes<=1073741824) and (.rehandshake.maximum_records<=1048576) and
  .authorization.local_api_remains_authoritative and .authorization.mutation_idempotency_required and .authorization.revocation_checked_each_session and .authorization.active_revocation_terminates_session and
  .relay=={can_decrypt:false,can_authorize:false,plaintext_logs:false} and
  .implementation.reviewed_noise_library_required and (.implementation.custom_cryptographic_primitives_allowed|not) and .implementation.third_party_review_required
' "$policy" >/dev/null
printf 'Bedrock remote transport threat-model policy is valid.\n'
