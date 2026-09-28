#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
command -v docker >/dev/null 2>&1 || { printf 'Docker is required for the disposable systemd test.\n' >&2; exit 1; }
stage="$root/os/config/includes.chroot/usr/share/bedrock/management-ui"
[ ! -e "$stage" ] && [ ! -L "$stage" ] || { printf 'Refusing to replace an existing management UI stage.\n' >&2; exit 1; }
container_id=
stage_created=0
cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ -n "$container_id" ]; then
    docker logs "$container_id" >&2 || true
    docker exec "$container_id" journalctl --no-pager -u bedrock-api -u bedrock-action-broker -u bedrock-remote-identity -u bedrock-web -u bedrock-web-identity >&2 || true
  fi
  if [ -n "$container_id" ]; then docker rm --force "$container_id" >/dev/null; fi
  if [ "$stage_created" -eq 1 ]; then rm -rf -- "$stage"; fi
  exit "$status"
}
trap cleanup EXIT INT TERM
BEDROCK_SOURCE_COMMIT=$(git -C "$root" rev-parse HEAD)
export BEDROCK_SOURCE_COMMIT
sh "$root/os/scripts/build-installed-ui.sh"
stage_created=1
container_id=$(docker run --detach --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --volume "$root:/workspace:ro" --workdir /workspace \
  --env container=docker --env BEDROCK_DISPOSABLE_SERVICE_TEST=1 --env BEDROCK_SERVICE_MANAGER=systemd \
  debian:13.6-slim sh -ec 'apt-get update -qq && apt-get install -y --no-install-recommends systemd systemd-sysv dbus python3 util-linux passwd jq openssl xxd ca-certificates nginx-light dialog chromium nodejs npm libnss3-tools >/dev/null && npm install --global --no-audit --no-fund agent-browser@0.38.1 >/dev/null && mount -o remount,rw /sys/fs/cgroup && mount --make-shared /run && exec /sbin/init')
ready=0
for attempt in $(seq 1 120); do
  [ "$(docker inspect --format '{{.State.Running}}' "$container_id")" = true ] || break
  if docker exec "$container_id" test -S /run/systemd/private; then ready=1; break; fi
  sleep 2
done
[ "$ready" -eq 1 ] || { printf 'systemd container did not become ready\n' >&2; exit 1; }
docker exec "$container_id" python3 os/tests/test-api-service-boundary.py
