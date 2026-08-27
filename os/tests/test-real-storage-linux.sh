#!/bin/sh
set -eu

[ "$(uname -s)" = Linux ] || { printf 'error: real storage integration requires Linux\n' >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { printf 'error: real storage integration requires root\n' >&2; exit 2; }
for tool in zpool zfs mdadm losetup mkfs.ext4 mount umount sha256sum testparm jq; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'error: missing integration tool: %s\n' "$tool" >&2; exit 2; }
done
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
pool="bedrockci$$"
md="bedrock-ci-$$"
loops=
cleanup() {
  set +e
  mountpoint -q "$work/md-mount" && umount "$work/md-mount"
  mdadm --stop "/dev/md/$md" >/dev/null 2>&1
  zpool list -H -o name "$pool" >/dev/null 2>&1 && zpool destroy -f "$pool"
  for loop in $loops; do losetup -d "$loop" >/dev/null 2>&1; done
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

mkdir -p "$work/zfs-mount" "$work/md-mount"
for disk in zfs-a zfs-b zfs-c; do truncate -s 256M "$work/$disk"; done
zpool create -f -O "mountpoint=$work/zfs-mount" "$pool" mirror "$work/zfs-a" "$work/zfs-b"
zfs create "$pool/files"
dd if=/dev/urandom of="$work/zfs-mount/files/payload.bin" bs=1M count=8 status=none
zfs_checksum=$(sha256sum "$work/zfs-mount/files/payload.bin" | awk '{print $1}')
zfs snapshot "$pool/files@acceptance"
zpool scrub "$pool"
zpool wait -t scrub "$pool"
zpool offline "$pool" "$work/zfs-a"
[ "$(zpool list -H -o health "$pool")" = DEGRADED ]
zpool replace "$pool" "$work/zfs-a" "$work/zfs-c"
zpool wait -t replace "$pool" 2>/dev/null || zpool wait -t resilver "$pool"
zpool export "$pool"
zpool import -d "$work" "$pool"
[ "$(sha256sum "$work/zfs-mount/files/payload.bin" | awk '{print $1}')" = "$zfs_checksum" ]
zfs destroy "$pool/files@acceptance"
zpool destroy "$pool"

for disk in md-a md-b md-c; do
  truncate -s 256M "$work/$disk"
  loop=$(losetup --find --show "$work/$disk")
  loops="$loops $loop"
  eval "${disk%%-*}_${disk##*-}=\$loop"
done
mdadm --create "/dev/md/$md" --metadata=1.2 --level=1 --raid-devices=2 "$md_a" "$md_b"
mdadm --wait "/dev/md/$md"
mkfs.ext4 -q -F "/dev/md/$md"
mount "/dev/md/$md" "$work/md-mount"
dd if=/dev/urandom of="$work/md-mount/payload.bin" bs=1M count=8 status=none
sync
md_checksum=$(sha256sum "$work/md-mount/payload.bin" | awk '{print $1}')
mdadm --manage "/dev/md/$md" --fail "$md_a" --remove "$md_a" --add "$md_c"
mdadm --wait "/dev/md/$md"
umount "$work/md-mount"
mdadm --stop "/dev/md/$md"
mdadm --assemble "/dev/md/$md" "$md_b" "$md_c"
mount "/dev/md/$md" "$work/md-mount"
[ "$(sha256sum "$work/md-mount/payload.bin" | awk '{print $1}')" = "$md_checksum" ]
umount "$work/md-mount"
mdadm --stop "/dev/md/$md"

jq -n '{schema:1,users:[],groups:[{name:"family",members:[],created_unix:1}],datasets:[],snapshots:[],shares:[
  {pool:"vault",name:"family",path:"/srv/bedrock/pools/vault/family",access_group:"family",protocols:["smb"],read_only:false,recycle:true,time_machine:false,created_unix:1},
  {pool:"vault",name:"timemachine",path:"/srv/bedrock/pools/vault/timemachine",access_group:"family",protocols:["smb"],read_only:false,recycle:false,time_machine:true,created_unix:1}]}' > "$work/nas.json"
BEDROCK_NAS_RENDER_TEST_MODE=1 "$ROOT/os/config/includes.chroot/usr/lib/bedrock/render-nas-services" "$work/nas.json" "$work/services" >/dev/null
testparm -s "$work/services/smb.conf" >/dev/null

printf 'Bedrock real disposable OpenZFS, Linux RAID, Samba, failure, replacement, import, and integrity tests passed.\n'
