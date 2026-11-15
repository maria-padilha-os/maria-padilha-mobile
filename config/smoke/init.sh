#!/bin/busybox sh
# PID 1 for the minimal QEMU serial smoke guest.
#
# This is not the Phosh image: it exists only to prove that the pinned kernel
# and a rootfs built from the pinned Alpine minirootfs reach userspace and
# write a known marker to the serial console. It never opens a block device,
# a network interface or a physical device.

set -eu

export PATH=/sbin:/usr/sbin:/bin:/usr/bin
export HOME=/

# Keep the guest side-effect free. The mounts are private to this initramfs
# and disappear when QEMU exits.
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

printf '\n%s\n' 'MARIA_PADILHA_QEMU_SMOKE_OK'
printf 'MARIA_PADILHA_SMOKE_ARCH=%s\n' "$(busybox uname -m)"
printf 'MARIA_PADILHA_SMOKE_KERNEL=%s\n' "$(busybox uname -r)"
printf 'MARIA_PADILHA_SMOKE_PID1=%s\n' "$$"

sync

# poweroff exits QEMU under -no-reboot. If the syscall is unavailable the
# kernel panics; the panic timeout and the host-side timeout both prevent a
# silent hang.
exec busybox poweroff -f
