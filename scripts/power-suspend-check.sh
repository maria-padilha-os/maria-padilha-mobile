#!/usr/bin/env bash
# Refuse to test suspend on the reference laptop or any desktop.
#
# This script never suspends anything. It classifies the current platform from
# sysfs and prints whether a suspend/resume test is allowed here. The actual
# test is a manual QEMU or supported-device step in
# docs/qemu-power-checklist.md.
#
# Exit status: 0 when the target is QEMU or a phone-class device, 1 when the
# target must not be used for a suspend test.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/power/power.conf
. "$ROOT/config/power/power.conf"

SYSFS="${POWER_SYSFS:-/sys}"

die() {
  printf 'FAIL %s\n' "$*" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage: scripts/power-suspend-check.sh [options]

Options:
  --sysfs DIR    inspect DIR instead of /sys
  -h, --help     show this help

This is a target guard, not a suspend action. It refuses laptops, desktops,
tablets and unclassified hosts. QEMU and phone-class devicetree targets are
allowed; use the manual checklist for the actual test.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sysfs)
      [ "$#" -ge 2 ] || die "--sysfs needs a directory"
      SYSFS="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

[ -d "$SYSFS" ] || die "sysfs path does not exist: $SYSFS"

read_value() {
  local file="$1"
  [ -r "$file" ] || {
    printf ''
    return 0
  }
  tr -d '\r\n\000' <"$file" 2>/dev/null || true
}

model=$(read_value "$SYSFS/firmware/devicetree/base/model")
compatible=$(read_value "$SYSFS/firmware/devicetree/base/compatible")
product=$(read_value "$SYSFS/class/dmi/id/product_name")
chassis=$(read_value "$SYSFS/class/dmi/id/chassis_type")
platform="unknown"

case " ${model} ${product} ${compatible} " in
  *QEMU* | *qemu* | *KVM* | *kvm* | *VirtualBox* | *VMware* | *Bochs*)
    platform="qemu"
    ;;
  *PinePhone* | *pinephone* | *Pine64* | *pine64* | *Librem* | *librem*)
    platform="phone"
    ;;
esac

if [ "$platform" = "unknown" ]; then
  case "$chassis" in
    8 | 9 | 10 | 14) platform="laptop" ;;
    30 | 31 | 32) platform="tablet" ;;
    3 | 4 | 5 | 6 | 7 | 15 | 16) platform="desktop" ;;
    "")
      if [ -n "$model" ] || [ -n "$compatible" ]; then
        platform="arm-device"
      fi
      ;;
  esac
fi

states=$(read_value "$SYSFS/power/state")
mem_sleep=$(read_value "$SYSFS/power/mem_sleep")
suspend_supported=false
case " $states " in
  *" mem "* | *" freeze "*) suspend_supported=true ;;
esac

printf 'platform: %s\n' "$platform"
printf 'model: %s\n' "${model:-${product:-unknown}}"
printf 'suspend states: %s\n' "${states:-none}"
printf 'mem_sleep: %s\n' "${mem_sleep:-none}"
printf 'suspend supported: %s\n' "$suspend_supported"

case "$platform" in
  qemu | phone)
    if [ "$suspend_supported" = false ]; then
      printf 'REFUSE: target is allowed, but the kernel exposes no suspend state\n'
      exit 1
    fi
    printf 'ALLOW: this target may run the manual suspend/resume checklist\n'
    printf 'This script did not suspend anything.\n'
    exit 0
    ;;
  laptop)
    printf 'REFUSE: a laptop chassis was detected; use QEMU or a supported device\n'
    exit 1
    ;;
  desktop | tablet)
    printf 'REFUSE: a %s was detected; use QEMU or a supported device\n' "$platform"
    exit 1
    ;;
  arm-device)
    printf 'REFUSE: unclassified ARM device; only a supported device or QEMU may suspend\n'
    exit 1
    ;;
  *)
    printf 'REFUSE: cannot prove this is QEMU or a supported device\n'
    exit 1
    ;;
esac
