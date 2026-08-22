#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CMDLINE="$ROOT/os/boot/bedrock-cmdline"
BUILDER="$ROOT/os/scripts/build-uki.sh"

[ -s "$CMDLINE" ] && [ -x "$BUILDER" ] || { printf 'error: verified boot inputs are missing\n' >&2; exit 1; }
grep -Eq '(^| )rd\.systemd\.verity=1( |$)' "$CMDLINE" || { printf 'error: dm-verity activation is required\n' >&2; exit 1; }
grep -Eq '(^| )systemd\.gpt_auto=1( |$)' "$CMDLINE" || { printf 'error: GPT auto-discovery is required\n' >&2; exit 1; }
if grep -Eq '(^| )(root=LABEL=|root=PARTLABEL=)' "$CMDLINE"; then
  printf 'error: duplicated root slots must not be selected by label\n' >&2
  exit 1
fi
grep -q 'roothash=' "$BUILDER" || { printf 'error: UKI must bind its slot to a dm-verity root hash\n' >&2; exit 1; }
grep -q -- '--secureboot-private-key=' "$BUILDER" || { printf 'error: UKI signing is required\n' >&2; exit 1; }

printf 'Bedrock verified boot configuration is valid.\n'
