#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
guided="$ROOT/os/installer/bedrock-install-guided.sh"
fixture="$ROOT/os/tests/fixtures/guided-installer"
inventory="$ROOT/os/tests/install-targets.json"
layout="$ROOT/os/layout/bedrock-amd64.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

run_guided() {
  BEDROCK_INSTALLER_TEST_MODE=1 \
  BEDROCK_TEST_INSTALL_PATH="$fixture:$PATH" \
  BEDROCK_TEST_INSTALL_SCANNER="$fixture/scanner" \
  BEDROCK_TEST_INSTALL_PLANNER="$ROOT/os/installer/create-install-plan.sh" \
  BEDROCK_TEST_INSTALL_REQUEST_CREATOR="$ROOT/os/installer/create-protected-install-request.sh" \
  BEDROCK_TEST_INSTALL_WRITER="$fixture/writer" \
  BEDROCK_TEST_INSTALL_INVENTORY="${BEDROCK_TEST_INSTALL_INVENTORY:-$inventory}" \
  BEDROCK_TEST_INSTALL_LOG="$work/writer.log" \
  BEDROCK_TEST_DIALOG_RESPONSES="$work/responses" \
  BEDROCK_TEST_LAYOUT="$layout" \
  BEDROCK_TEST_REQUEST_SESSION=123e4567-e89b-42d3-a456-426614174000 \
  BEDROCK_TEST_NOW_UNIX=1787617000 \
    sh "$guided"
}

confirmation='INSTALL BEDROCK — Test System SSD — /dev/nvme1n1 — 68719476736'
printf 'linux:install-safe\n%s\nreturn\n' "$confirmation" > "$work/responses"
: > "$work/writer.log"
run_guided
grep -q '^writer linux:install-safe$' "$work/writer.log"
[ ! -s "$work/responses" ]

printf 'linux:install-safe\nWRONG DRIVE\n' > "$work/responses"
: > "$work/writer.log"
if run_guided >/dev/null 2>&1; then
  printf 'error: guided installer accepted an incorrect erase phrase\n' >&2
  exit 1
fi
[ ! -s "$work/writer.log" ]

jq '(.targets[] | select(.id == "linux:install-safe") | .system) = true' \
  "$inventory" > "$work/no-targets.json"
: > "$work/responses"
: > "$work/writer.log"
BEDROCK_TEST_INSTALL_INVENTORY="$work/no-targets.json" run_guided >/dev/null 2>&1 || status=$?
[ "${status:-0}" -ne 0 ] || { printf 'error: guided installer accepted no eligible target\n' >&2; exit 1; }
[ ! -s "$work/writer.log" ]

grep -q '^ConditionPathExists=!/run/live/medium/bedrock/bedrock-os-amd64.raw$' \
  "$ROOT/os/config/includes.chroot/usr/lib/systemd/system/bedrock-first-run.service"
grep -q '^ConditionPathExists=/run/live/medium/bedrock/bedrock-os-amd64.raw$' \
  "$ROOT/os/installer/bedrock-install.service"

printf 'Bedrock guided on-server installer tests passed.\n'
