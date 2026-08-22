#!/bin/sh
set -eu

[ "$#" -eq 2 ] || { printf 'usage: %s ROOTFS KERNEL_VERSION\n' "$0" >&2; exit 2; }
rootfs=$1
kernel_version=$2
[ -d "$rootfs/usr/lib/modules/$kernel_version" ] || { printf 'error: kernel modules are missing\n' >&2; exit 1; }
[ -x "$rootfs/usr/bin/dracut" ] || { printf 'error: dracut-core is required in the root filesystem\n' >&2; exit 1; }

output="/boot/initrd.img-bedrock-$kernel_version"
mounted=""
cleanup() {
  for target in $mounted; do
    umount "$target" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

mount_virtual() {
  target=$1
  type=$2
  source=$3
  if ! mountpoint -q "$rootfs$target"; then
    mount -t "$type" "$source" "$rootfs$target"
    mounted="$rootfs$target $mounted"
  fi
}

mount_virtual /proc proc proc
mount_virtual /sys sysfs sysfs
if ! mountpoint -q "$rootfs/dev"; then
  mount --bind /dev "$rootfs/dev"
  mounted="$rootfs/dev $mounted"
fi

chroot "$rootfs" dracut --force --no-hostonly --add 'systemd systemd-veritysetup crypt dm' "$output" "$kernel_version"
[ -s "$rootfs$output" ] || { printf 'error: installed-system initramfs was not created\n' >&2; exit 1; }
printf '%s\n' "$rootfs$output"
