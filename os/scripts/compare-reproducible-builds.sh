#!/bin/sh
set -eu

[ "$#" -eq 2 ] || { printf 'usage: %s BUILD_A_DIR BUILD_B_DIR\n' "$0" >&2; exit 2; }
a=$1
b=$2
for directory in "$a" "$b"; do [ -d "$directory" ] || { printf 'error: build directory is missing\n' >&2; exit 1; }; done

iso_name=bedrock-os-amd64.iso
for file in "$iso_name" "$iso_name.sha256" packages.lock bedrock-build-manifest.json; do
  [ -s "$a/$file" ] && [ -s "$b/$file" ] || { printf 'error: reproducibility input is missing: %s\n' "$file" >&2; exit 1; }
done
(cd "$a" && sha256sum -c "$iso_name.sha256" >/dev/null)
(cd "$b" && sha256sum -c "$iso_name.sha256" >/dev/null)
hash_a=$(sha256sum "$a/$iso_name" | awk '{print $1}')
hash_b=$(sha256sum "$b/$iso_name" | awk '{print $1}')
[ "$hash_a" = "$hash_b" ] || { printf 'error: ISO builds are not byte-for-byte reproducible\n' >&2; exit 1; }
cmp -s "$a/packages.lock" "$b/packages.lock" || { printf 'error: resolved package sets differ\n' >&2; exit 1; }
cmp -s "$a/bedrock-build-manifest.json" "$b/bedrock-build-manifest.json" || { printf 'error: build manifests differ\n' >&2; exit 1; }
if [ -e "$a/bedrock-os.spdx.json" ] || [ -e "$b/bedrock-os.spdx.json" ]; then
  [ -s "$a/bedrock-os.spdx.json" ] && [ -s "$b/bedrock-os.spdx.json" ] || { printf 'error: only one reproducibility input contains the SPDX SBOM\n' >&2; exit 1; }
  cmp -s "$a/bedrock-os.spdx.json" "$b/bedrock-os.spdx.json" || { printf 'error: SPDX SBOMs differ\n' >&2; exit 1; }
else
  jq -e '.sbom.format=="SPDX-2.3-json" and (.sbom.sha256|test("^[0-9a-f]{64}$")) and (.sbom.package_count|type=="number" and floor==. and .>0)' "$a/bedrock-build-manifest.json" >/dev/null || { printf 'error: build manifest lacks reproducible SPDX evidence\n' >&2; exit 1; }
fi
printf 'Bedrock ISO is byte-for-byte reproducible across both clean builds (%s).\n' "$hash_a"
