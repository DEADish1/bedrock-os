#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
builder="$ROOT/os/installer/build-protected-system-writer.sh"
launcher="$ROOT/os/installer/write-protected-install.sh"
finalizer="$ROOT/os/installer/finalize-protected-layout.sh"
source_file="$ROOT/os/installer/protected-system-writer.rs"

sh -n "$builder"
sh -n "$launcher"
sh -n "$finalizer"
grep -q 'O_EXCL | O_NONBLOCK | O_NOFOLLOW' "$source_file"
grep -q 'BLKGETSIZE64' "$source_file"
grep -q 'sync_all()' "$source_file"
grep -q 'failed full reread verification' "$source_file"
grep -q 'layout_finalized.*false' "$source_file"
grep -q 'mknod.*target.*major.*minor' "$finalizer"
grep -q 'blockdev --rereadpt' "$finalizer"
grep -q 'blockdev --flushbufs' "$finalizer"
grep -q 'udevadm settle --timeout=30' "$finalizer"
grep -q 'e2fsck -f -y' "$finalizer"
grep -q 'resize2fs' "$finalizer"
grep -q 'persistent_state_checked: true' "$finalizer"

if BEDROCK_INSTALLER_TEST_MODE=1 sh "$launcher" /does/not/exist >/dev/null 2>&1; then
  printf 'error: physical system writer accepted installer test mode\n' >&2
  exit 1
fi

if BEDROCK_INSTALLER_TEST_MODE=1 sh "$finalizer" 8 0 4096 >/dev/null 2>&1; then
  printf 'error: protected layout finalizer accepted installer test mode\n' >&2
  exit 1
fi

if ! command -v rustc >/dev/null 2>&1; then
  printf 'Bedrock protected system-writer compile test skipped: rustc unavailable.\n'
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
sh "$builder" "$work/disabled-writer"
if "$work/disabled-writer" /does/not/exist /dev/does-not-exist 1 1 \
  0000000000000000000000000000000000000000000000000000000000000000 >/dev/null 2>&1; then
  printf 'error: default system-writer build did not fail closed\n' >&2
  exit 1
fi

rustc --edition=2021 --test "$source_file" -o "$work/writer-tests"
"$work/writer-tests" >/dev/null

BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER=I_ACCEPT_REAL_SYSTEM_DISK_DATA_LOSS \
BEDROCK_REQUIRE_PRODUCTION_TRUST=1 \
  sh "$builder" "$work/gated-writer"
[ -x "$work/gated-writer" ] || { printf 'error: gated system writer was not compiled\n' >&2; exit 1; }

if BEDROCK_ENABLE_SYSTEM_PHYSICAL_WRITER=WRONG BEDROCK_REQUIRE_PRODUCTION_TRUST=1 \
  sh "$builder" "$work/invalid-writer" >/dev/null 2>&1; then
  printf 'error: invalid system-writer build token was accepted\n' >&2
  exit 1
fi

printf 'Bedrock protected system-writer gate and non-device tests passed.\n'
