#!/bin/sh
set -eu

[ "$#" -eq 7 ] || {
  printf 'usage: create-spdx-sbom.sh PACKAGES OUTPUT VERSION DISTRIBUTION ARCHITECTURE COMMIT SOURCE_DATE_EPOCH\n' >&2
  exit 1
}

packages=$1
output=$2
version=$3
distribution=$4
architecture=$5
commit=$6
epoch=$7

[ -f "$packages" ] && [ ! -L "$packages" ] || { printf 'error: package lock is missing or indirect\n' >&2; exit 1; }
case $epoch in ''|*[!0-9]*) printf 'error: source date epoch is invalid\n' >&2; exit 1;; esac
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required\n' >&2; exit 1; }

created=$(date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ')
identity=$(printf '%s\n%s\n%s\n%s\n%s\n' "$version" "$distribution" "$architecture" "$commit" "$(sha256sum "$packages" | cut -d' ' -f1)" | sha256sum | cut -d' ' -f1)
temporary="${output}.tmp.$$"
trap 'rm -f "$temporary"' EXIT INT TERM

jq -Rn \
  --rawfile locked "$packages" \
  --arg created "$created" \
  --arg version "$version" \
  --arg distribution "$distribution" \
  --arg architecture "$architecture" \
  --arg commit "$commit" \
  --arg identity "$identity" '
  def entries:
    $locked | split("\n") | map(select(length > 0)) |
    map(capture("^(?<name>[^=]+)=(?<version>.+)$"));
  (entries) as $entries |
  {
    spdxVersion: "SPDX-2.3",
    dataLicense: "CC0-1.0",
    SPDXID: "SPDXRef-DOCUMENT",
    name: ("Bedrock-Server-OS-" + $version + "-" + $architecture),
    documentNamespace: ("https://github.com/DEADish1/bedrock-os/sbom/" + $identity),
    creationInfo: {
      created: $created,
      creators: ["Organization: Bedrock Server OS Project", "Tool: bedrock-create-spdx-sbom-1"]
    },
    documentDescribes: ["SPDXRef-Bedrock-Server-OS"],
    packages: ([{
      SPDXID: "SPDXRef-Bedrock-Server-OS",
      name: "Bedrock Server OS",
      versionInfo: $version,
      supplier: "Organization: Bedrock Server OS Project",
      downloadLocation: "NOASSERTION",
      filesAnalyzed: false,
      licenseConcluded: "NOASSERTION",
      licenseDeclared: "NOASSERTION",
      copyrightText: "NOASSERTION",
      primaryPackagePurpose: "OPERATING-SYSTEM",
      externalRefs: [{referenceCategory:"OTHER",referenceType:"bedrock-source-commit",referenceLocator:$commit}],
      comment: ("Distribution: " + $distribution + "; architecture: " + $architecture)
    }] + ($entries | to_entries | map({
      SPDXID: ("SPDXRef-DebianPackage-" + ((.key + 1)|tostring)),
      name: .value.name,
      versionInfo: .value.version,
      supplier: "Organization: Debian",
      downloadLocation: "NOASSERTION",
      filesAnalyzed: false,
      licenseConcluded: "NOASSERTION",
      licenseDeclared: "NOASSERTION",
      copyrightText: "NOASSERTION",
      primaryPackagePurpose: "LIBRARY",
      externalRefs: [{referenceCategory:"PACKAGE-MANAGER",referenceType:"purl",referenceLocator:("pkg:deb/debian/" + .value.name + "@" + (.value.version|@uri) + "?arch=" + $architecture)}]
    }))),
    relationships: ($entries | to_entries | map({
      spdxElementId: "SPDXRef-Bedrock-Server-OS",
      relationshipType: "CONTAINS",
      relatedSpdxElement: ("SPDXRef-DebianPackage-" + ((.key + 1)|tostring))
    }))
  }' > "$temporary"

jq -e '.spdxVersion=="SPDX-2.3" and .dataLicense=="CC0-1.0" and (.packages|length>=1)' "$temporary" >/dev/null
chmod 0644 "$temporary"
mv "$temporary" "$output"
trap - EXIT INT TERM
