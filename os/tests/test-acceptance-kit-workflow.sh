#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
workflow="$ROOT/.github/workflows/os-image.yml"
notice="$ROOT/installer/desktop/ACCEPTANCE-NOTICE.txt"

[ -f "$workflow" ] && [ ! -L "$workflow" ] || {
  printf 'error: OS image workflow is missing or indirect\n' >&2
  exit 1
}
[ -f "$notice" ] && [ ! -L "$notice" ] || {
  printf 'error: acceptance notice is missing or indirect\n' >&2
  exit 1
}

require_workflow_text() {
  grep -F -- "$1" "$workflow" >/dev/null || {
    printf 'error: acceptance-kit workflow contract is missing: %s\n' "$1" >&2
    exit 1
  }
}

require_workflow_text 'acceptance-kit:'
require_workflow_text 'if: ${{ inputs.protected_writer_acceptance }}'
require_workflow_text 'needs: [build, reproducibility]'
require_workflow_text '.protected_system_writer_enabled == true'
require_workflow_text '.signing_mode == "development-ephemeral" and .release_eligible == false'
require_workflow_text 'BEDROCK_ENABLE_PHYSICAL_WRITER=I_ACCEPT_REAL_DEVICE_DATA_LOSS'
require_workflow_text 'create-signed-image-release.sh'
require_workflow_text 'verify-signed-image.sh acceptance-kit/media'
require_workflow_text 'prepare-release-sidecar.mjs'
require_workflow_text 'retention-days: 7'
require_workflow_text 'acceptance-trust-certificate.pem'

grep -F 'NOT A RELEASE' "$notice" >/dev/null
grep -F 'uses an ephemeral development certificate' "$notice" >/dev/null
grep -F 'does not authorize a disk write' "$notice" >/dev/null

printf 'Bedrock short-lived acceptance-kit workflow contract is valid.\n'
