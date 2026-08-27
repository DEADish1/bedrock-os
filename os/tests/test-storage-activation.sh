#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script="$ROOT/os/config/includes.chroot/usr/lib/bedrock/mount-storage-resources"
service="$ROOT/os/config/includes.chroot/usr/lib/systemd/system/bedrock-storage-activation.service"
link="$ROOT/os/config/includes.chroot/etc/systemd/system/multi-user.target.wants/bedrock-storage-activation.service"
sh -n "$script"
grep -q '^Before=smbd.service nfs-server.service bedrock-storage-health.service$' "$service"
grep -q '^ReadWritePaths=/srv/bedrock /run /var/lib/bedrock/storage$' "$service"
[ -L "$link" ] && [ "$(readlink "$link")" = '../../../../usr/lib/systemd/system/bedrock-storage-activation.service' ] || {
  printf 'error: storage activation service is not enabled correctly\n' >&2; exit 1;
}
printf 'Bedrock managed storage boot-activation contract tests passed.\n'
