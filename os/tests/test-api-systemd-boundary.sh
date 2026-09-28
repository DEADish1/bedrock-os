#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
command -v docker >/dev/null 2>&1 || { printf 'Docker is required for the disposable systemd test.\n' >&2; exit 1; }
container_id=$(docker run --detach --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --volume "$root:/workspace:ro" --workdir /workspace \
  --env container=docker --env BEDROCK_DISPOSABLE_SERVICE_TEST=1 --env BEDROCK_SERVICE_MANAGER=systemd \
  debian:13.6-slim sh -ec 'apt-get update -qq && apt-get install -y --no-install-recommends systemd systemd-sysv dbus python3 util-linux passwd jq openssl xxd ca-certificates nginx-light dialog >/dev/null && mount -o remount,rw /sys/fs/cgroup && mount --make-shared /run && exec /sbin/init')
cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    docker logs "$container_id" >&2 || true
    docker exec "$container_id" journalctl --no-pager -u bedrock-api -u bedrock-action-broker -u bedrock-remote-identity -u bedrock-web -u bedrock-web-identity >&2 || true
  fi
  docker rm --force "$container_id" >/dev/null
  exit "$status"
}
trap cleanup EXIT INT TERM
ready=0
for attempt in $(seq 1 120); do
  [ "$(docker inspect --format '{{.State.Running}}' "$container_id")" = true ] || break
  if docker exec "$container_id" test -S /run/systemd/private; then ready=1; break; fi
  sleep 2
done
[ "$ready" -eq 1 ] || { printf 'systemd container did not become ready\n' >&2; exit 1; }
docker exec "$container_id" python3 os/tests/test-api-service-boundary.py
