#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
[ "$#" -eq 1 ] || { printf 'usage: %s OUTPUT\n' "$0" >&2; exit 2; }
output=$1
command -v rustc >/dev/null 2>&1 || { printf 'error: rustc is required\n' >&2; exit 2; }
[ -d "$(dirname -- "$output")" ] || { printf 'error: output directory does not exist\n' >&2; exit 1; }
[ ! -L "$output" ] || { printf 'error: writer output cannot be a symbolic link\n' >&2; exit 1; }

cfg=
if [ -n "${BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER:-}" ]; then
  [ "$BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER" = I_ACCEPT_REAL_SYSTEM_DISK_DATA_LOSS ] || {
    printf 'error: invalid physical system-writer build token\n' >&2
    exit 1
  }
  [ "${BEDROCK_REQUIRE_PRODUCTION_TRUST:-0}" = 1 ] || {
    printf 'error: physical system-writer builds require production trust\n' >&2
    exit 1
  }
  [ "$(uname -s)" = Linux ] || { printf 'error: the physical system writer supports Linux only\n' >&2; exit 1; }
  cfg='--cfg=bedrock_system_physical_writer'
fi

# shellcheck disable=SC2086
rustc --edition=2021 -C opt-level=2 -C strip=symbols $cfg \
  "$ROOT/os/installer/protected-system-writer.rs" -o "$output"
chmod 0755 "$output"
