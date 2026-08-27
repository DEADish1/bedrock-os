#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
bundle_validator="$ROOT/os/tests/validate-0.2-0.3-acceptance.sh"
boot_validator="$ROOT/os/tests/validate-boot-test-report.sh"
usb_validator="$ROOT/installer/acceptance/validate-real-device-report.sh"
install_validator="$ROOT/os/tests/validate-install-acceptance-report.sh"

usage() {
  cat >&2 <<EOF
usage:
  $0 init VERIFIED_IMAGE EVIDENCE_DIRECTORY
  $0 status EVIDENCE_DIRECTORY

This helper creates and checks report storage only. It never opens or writes a disk.
EOF
  exit 2
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    printf 'error: sha256sum, shasum, or openssl is required\n' >&2
    exit 2
  fi
}

valid_sha() {
  case "$1" in
    *[!0-9a-f]*|'') return 1 ;;
  esac
  [ "${#1}" -eq 64 ]
}

require_workspace() {
  workspace_dir=$1
  [ -d "$workspace_dir" ] && [ ! -L "$workspace_dir" ] || {
    printf 'error: evidence directory is missing or indirect: %s\n' "$workspace_dir" >&2
    exit 2
  }
  [ -f "$workspace_dir/IMAGE_SHA256" ] && [ ! -L "$workspace_dir/IMAGE_SHA256" ] || {
    printf 'error: evidence directory has no direct IMAGE_SHA256 file; run init first\n' >&2
    exit 2
  }
  image_sha256=$(cat -- "$workspace_dir/IMAGE_SHA256")
  valid_sha "$image_sha256" || {
    printf 'error: evidence directory contains an invalid image SHA-256\n' >&2
    exit 2
  }
}

init_workspace() {
  image_file=$1
  workspace_dir=$2

  [ -f "$image_file" ] && [ ! -L "$image_file" ] || {
    printf 'error: verified image must be a direct regular file: %s\n' "$image_file" >&2
    exit 2
  }
  if [ -e "$workspace_dir" ] || [ -L "$workspace_dir" ]; then
    [ -d "$workspace_dir" ] && [ ! -L "$workspace_dir" ] || {
      printf 'error: evidence destination is not a direct directory: %s\n' "$workspace_dir" >&2
      exit 2
    }
  else
    mkdir -m 700 -- "$workspace_dir"
  fi

  image_sha256=$(sha256_file "$image_file")
  valid_sha "$image_sha256" || {
    printf 'error: could not calculate a valid image SHA-256\n' >&2
    exit 2
  }

  if [ -e "$workspace_dir/IMAGE_SHA256" ] || [ -L "$workspace_dir/IMAGE_SHA256" ]; then
    [ -f "$workspace_dir/IMAGE_SHA256" ] && [ ! -L "$workspace_dir/IMAGE_SHA256" ] || {
      printf 'error: existing IMAGE_SHA256 is not a direct regular file\n' >&2
      exit 2
    }
    existing_sha=$(cat -- "$workspace_dir/IMAGE_SHA256")
    [ "$existing_sha" = "$image_sha256" ] || {
      printf 'error: evidence directory is already bound to a different image\n' >&2
      exit 1
    }
  else
    sha_tmp=$(mktemp "$workspace_dir/.IMAGE_SHA256.XXXXXX")
    trap 'rm -f -- "$sha_tmp"' EXIT INT TERM
    printf '%s\n' "$image_sha256" > "$sha_tmp"
    chmod 600 "$sha_tmp"
    mv -- "$sha_tmp" "$workspace_dir/IMAGE_SHA256"
    trap - EXIT INT TERM
  fi

  printf 'Evidence workspace is bound to image %s.\n' "$image_sha256"
  printf 'Collect: vmware.json, hyper-v-generation-2.json, physical-intel.json, physical-amd.json, disposable-usb.json, disposable-system-install.json\n'
  printf 'No disk was opened or written.\n'
}

report_status=0

check_report() {
  label=$1
  report_file=$2
  validator=$3
  jq_filter=$4

  if [ ! -e "$report_file" ] && [ ! -L "$report_file" ]; then
    printf '[missing] %s\n' "$label"
    report_status=1
    return
  fi
  if [ ! -f "$report_file" ] || [ -L "$report_file" ]; then
    printf '[invalid] %s — report must be a direct regular file\n' "$label"
    report_status=1
    return
  fi
  if ! sh "$validator" "$report_file" >/dev/null 2>&1 ||
     ! jq -e --arg sha "$image_sha256" "$jq_filter" "$report_file" >/dev/null 2>&1; then
    printf '[invalid] %s — validator, role, or image SHA-256 did not match\n' "$label"
    report_status=1
    return
  fi
  printf '[ok]      %s\n' "$label"
}

status_workspace() {
  workspace_dir=$1
  require_workspace "$workspace_dir"
  command -v jq >/dev/null 2>&1 || {
    printf 'error: jq is required\n' >&2
    exit 2
  }

  check_report 'VMware UEFI, two healthy boots' \
    "$workspace_dir/vmware.json" "$boot_validator" \
    '.image_sha256 == $sha and .platform == "vmware" and .platform_generation == null'
  check_report 'Hyper-V Generation 2, two healthy boots' \
    "$workspace_dir/hyper-v-generation-2.json" "$boot_validator" \
    '.image_sha256 == $sha and .platform == "hyper-v" and .platform_generation == "generation-2"'
  check_report 'Physical Intel, two healthy boots' \
    "$workspace_dir/physical-intel.json" "$boot_validator" \
    '.image_sha256 == $sha and .platform == "physical" and .cpu_vendor == "intel"'
  check_report 'Physical AMD, two healthy boots' \
    "$workspace_dir/physical-amd.json" "$boot_validator" \
    '.image_sha256 == $sha and .platform == "physical" and .cpu_vendor == "amd"'
  check_report 'Disposable USB write, reread, UEFI boot, guided installer' \
    "$workspace_dir/disposable-usb.json" "$usb_validator" \
    '.image_sha256 == $sha'
  check_report 'Disposable system-disk install, first run, persistent reboot' \
    "$workspace_dir/disposable-system-install.json" "$install_validator" \
    '.image_sha256 == $sha'

  [ "$report_status" -eq 0 ] || {
    printf 'Acceptance is still open for image %s.\n' "$image_sha256"
    return 1
  }

  sh "$bundle_validator" "$image_sha256" \
    "$workspace_dir/vmware.json" \
    "$workspace_dir/hyper-v-generation-2.json" \
    "$workspace_dir/physical-intel.json" \
    "$workspace_dir/physical-amd.json" \
    "$workspace_dir/disposable-usb.json" \
    "$workspace_dir/disposable-system-install.json"
}

case "${1-}" in
  init)
    [ "$#" -eq 3 ] || usage
    init_workspace "$2" "$3"
    ;;
  status)
    [ "$#" -eq 2 ] || usage
    status_workspace "$2"
    ;;
  *) usage ;;
esac
