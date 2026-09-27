#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
command -v docker >/dev/null 2>&1 || { printf 'Docker is required for the disposable API service-boundary test.\n' >&2; exit 1; }
docker run --rm --volume "$root:/workspace:ro" --workdir /workspace \
  --env BEDROCK_DISPOSABLE_SERVICE_TEST=1 debian:13.6-slim \
  sh -ec 'apt-get update -qq && apt-get install -y --no-install-recommends python3 util-linux passwd jq openssl ca-certificates >/dev/null && python3 os/tests/test-api-service-boundary.py'
