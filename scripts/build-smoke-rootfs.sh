#!/usr/bin/env bash
# Build the unprivileged minimal rootfs used by the QEMU serial smoke test.
#
# The guest is an initramfs assembled from the pinned Alpine aarch64 minirootfs
# and the pinned Alpine virt kernel. Nothing here needs root: no chroot, no
# mount, no loop device and no image partition table. The full pmbootstrap
# image remains a separate builder-only path.

set -euo pipefail
umask 022

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
. "$ROOT/scripts/lib.sh"

OUT_OVERRIDE=""
CACHE_OVERRIDE=""
KERNEL_INPUT=""
ROOTFS_INPUT=""

usage() {
  cat <<'EOF'
Usage: scripts/build-smoke-rootfs.sh [options]

Options:
  --out DIR        output directory (default: out/smoke)
  --cache DIR      download cache (default: .scratch/smoke-cache)
  --kernel FILE    use an already downloaded pinned kernel
  --rootfs FILE    use an already downloaded pinned minirootfs tarball
  -h, --help       show this help

Downloads are release artifacts pinned by SHA-256 in config/smoke.conf. A
cached file with the wrong hash is discarded and fetched again. The resulting
initramfs and kernel are checksummed into the output directory.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out)
      [ "$#" -ge 2 ] || die "--out needs a directory"
      OUT_OVERRIDE="$2"
      shift
      ;;
    --cache)
      [ "$#" -ge 2 ] || die "--cache needs a directory"
      CACHE_OVERRIDE="$2"
      shift
      ;;
    --kernel)
      [ "$#" -ge 2 ] || die "--kernel needs a file"
      KERNEL_INPUT="$2"
      shift
      ;;
    --rootfs)
      [ "$#" -ge 2 ] || die "--rootfs needs a file"
      ROOTFS_INPUT="$2"
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

load_config
validate_config

require_command curl
require_command python3
require_command sha256sum
require_command tar

abs_path() {
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

CACHE_DIR=$(abs_path "${CACHE_OVERRIDE:-$SMOKE_CACHE_DIR}")
SMOKE_OUT=$(abs_path "${OUT_OVERRIDE:-$SMOKE_OUT_DIR}")
BUILD_DIR=$(abs_path "$SMOKE_BUILD_DIR")

case "$CACHE_DIR" in
  "$ROOT"/.scratch/*) ;;
  *) die "smoke cache must stay under $ROOT/.scratch: $CACHE_DIR" ;;
esac
case "$SMOKE_OUT" in
  "$ROOT"/out/*) ;;
  *) die "smoke output must stay under $ROOT/out: $SMOKE_OUT" ;;
esac
case "$BUILD_DIR" in
  "$ROOT"/.scratch/*) ;;
  *) die "smoke build directory must stay under $ROOT/.scratch: $BUILD_DIR" ;;
esac

sha256_of() {
  sha256sum "$1" | cut -d' ' -f1
}

verify_pinned() {
  local label="$1" file="$2" expected="$3" actual
  [ -f "$file" ] || die "missing $label: $file"
  actual=$(sha256_of "$file")
  [ "$actual" = "$expected" ] ||
    die "$label checksum mismatch: expected $expected, got $actual ($file)"
  ok "$label checksum verifies"
}

fetch_pinned() {
  local label="$1" url="$2" expected="$3" destination="$4"
  local temporary="$destination.part.$$"

  if [ -f "$destination" ]; then
    if [ "$(sha256_of "$destination")" = "$expected" ]; then
      ok "$label restored from cache"
      return 0
    fi
    log "cached $label checksum is wrong; discarding $destination"
    rm -f -- "$destination"
  fi

  log "downloading $label: $url"
  if ! curl --fail --location --silent --show-error \
    --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 300 \
    --output "$temporary" "$url"; then
    rm -f -- "$temporary"
    die "could not download $label from $url"
  fi

  local actual
  actual=$(sha256_of "$temporary")
  if [ "$actual" != "$expected" ]; then
    rm -f -- "$temporary"
    die "$label checksum mismatch: expected $expected, got $actual"
  fi

  mv -f -- "$temporary" "$destination" || die "cannot store $label in $destination"
  ok "$label downloaded and verified"
}

mkdir -p -- "$CACHE_DIR" "$SMOKE_OUT" "$BUILD_DIR" ||
  die "cannot create smoke build/cache/output directories"

kernels_cache="$CACHE_DIR/alpine-$SMOKE_ALPINE_RELEASE-$SMOKE_ARCH-vmlinuz-virt"
rootfs_cache="$CACHE_DIR/alpine-$SMOKE_ALPINE_RELEASE-$SMOKE_ARCH-minirootfs.tar.gz"

if [ -n "$KERNEL_INPUT" ]; then
  kernel_file=$(abs_path "$KERNEL_INPUT")
  verify_pinned "kernel" "$kernel_file" "$SMOKE_KERNEL_SHA256"
else
  fetch_pinned "kernel" "$SMOKE_KERNEL_URL" "$SMOKE_KERNEL_SHA256" "$kernels_cache"
  kernel_file="$kernels_cache"
fi

if [ -n "$ROOTFS_INPUT" ]; then
  rootfs_tar=$(abs_path "$ROOTFS_INPUT")
  verify_pinned "minirootfs" "$rootfs_tar" "$SMOKE_ROOTFS_SHA256"
else
  fetch_pinned "minirootfs" "$SMOKE_ROOTFS_URL" "$SMOKE_ROOTFS_SHA256" "$rootfs_cache"
  rootfs_tar="$rootfs_cache"
fi

download_bytes=$(( $(stat -c '%s' "$kernel_file") + $(stat -c '%s' "$rootfs_tar") ))
download_limit=$((SMOKE_DOWNLOAD_BUDGET_MIB * 1024 * 1024))
[ "$download_bytes" -le "$download_limit" ] ||
  die "pinned downloads are $download_bytes bytes, over the ${SMOKE_DOWNLOAD_BUDGET_MIB} MiB budget"
ok "pinned downloads: $download_bytes bytes (budget ${SMOKE_DOWNLOAD_BUDGET_MIB} MiB)"

work=$(mktemp -d "$BUILD_DIR/work.XXXXXX") || die "cannot create a work directory"
cleanup() {
  rm -rf -- "$work"
}
trap cleanup EXIT

rootfs_dir="$work/rootfs"
mkdir -p -- "$rootfs_dir"
tar -xzf "$rootfs_tar" -C "$rootfs_dir" --no-same-owner ||
  die "cannot unpack the pinned minirootfs"

# The minirootfs has /sbin/init, but the smoke guest deliberately boots a tiny
# PID 1 so the marker is independent of the distro's init and services.
cp -f -- "$ROOT/$SMOKE_INIT_CONFIG" "$rootfs_dir/init" ||
  die "cannot install the smoke init"
chmod 0755 "$rootfs_dir/init"

mkdir -p -- "$rootfs_dir/proc" "$rootfs_dir/sys" "$rootfs_dir/dev" \
  "$rootfs_dir/run" "$rootfs_dir/tmp"
chmod 1777 "$rootfs_dir/tmp"

initramfs_tmp="$work/$SMOKE_INITRAMFS_NAME"
python3 "$ROOT/scripts/smoke-cpio.py" --root "$rootfs_dir" --output "$initramfs_tmp" ||
  die "cannot pack the smoke initramfs"

cp -f -- "$initramfs_tmp" "$SMOKE_OUT/$SMOKE_INITRAMFS_NAME" ||
  die "cannot write out/$SMOKE_INITRAMFS_NAME"
if [ "$(abs_path "$kernel_file")" != "$(abs_path "$SMOKE_OUT/$SMOKE_KERNEL_NAME")" ]; then
  cp -f -- "$kernel_file" "$SMOKE_OUT/$SMOKE_KERNEL_NAME" ||
    die "cannot write out/$SMOKE_KERNEL_NAME"
fi
chmod 0644 "$SMOKE_OUT/$SMOKE_KERNEL_NAME" "$SMOKE_OUT/$SMOKE_INITRAMFS_NAME"

kernel_bytes=$(stat -c '%s' "$SMOKE_OUT/$SMOKE_KERNEL_NAME")
initramfs_bytes=$(stat -c '%s' "$SMOKE_OUT/$SMOKE_INITRAMFS_NAME")
artifact_bytes=$((kernel_bytes + initramfs_bytes))
artifact_limit=$((SMOKE_ARTIFACT_BUDGET_MIB * 1024 * 1024))
[ "$artifact_bytes" -le "$artifact_limit" ] ||
  die "smoke artifact is $artifact_bytes bytes, over the ${SMOKE_ARTIFACT_BUDGET_MIB} MiB budget"

(
  cd "$SMOKE_OUT" || exit 1
  sha256sum "$SMOKE_KERNEL_NAME" >"$SMOKE_KERNEL_NAME.sha256"
  sha256sum "$SMOKE_INITRAMFS_NAME" >"$SMOKE_INITRAMFS_NAME.sha256"
) || die "cannot write smoke artifact checksums"

(
  cd "$ROOT" || exit 1
  printf '%s\0' \
    config/build.conf \
    config/smoke.conf \
    config/smoke/init.sh \
    devices/qemu-aarch64/device.conf \
    scripts/build-smoke-rootfs.sh \
    scripts/qemu-smoke.sh \
    scripts/smoke-cpio.py \
    Makefile \
    .github/workflows/ci.yml \
    docs/ci.md \
    README.md |
    xargs -0 sha256sum --
) >"$SMOKE_OUT/smoke-inputs.sha256" || die "cannot checksum smoke inputs"
(
  cd "$SMOKE_OUT" || exit 1
  sha256sum smoke-inputs.sha256 >smoke-inputs.digest
) || die "cannot checksum the smoke input manifest"

kernel_sha=$(cut -d' ' -f1 "$SMOKE_OUT/$SMOKE_KERNEL_NAME.sha256")
initramfs_sha=$(cut -d' ' -f1 "$SMOKE_OUT/$SMOKE_INITRAMFS_NAME.sha256")
cat >"$SMOKE_OUT/$SMOKE_MANIFEST" <<EOF
smoke_config_version=$SMOKE_CONFIG_VERSION
arch=$SMOKE_ARCH
alpine_release=$SMOKE_ALPINE_RELEASE
kernel_version=$SMOKE_KERNEL_VERSION
kernel_url=$SMOKE_KERNEL_URL
kernel_sha256=$SMOKE_KERNEL_SHA256
rootfs_url=$SMOKE_ROOTFS_URL
rootfs_sha256=$SMOKE_ROOTFS_SHA256
marker=$SMOKE_MARKER
kernel_bytes=$kernel_bytes
initramfs_bytes=$initramfs_bytes
artifact_bytes=$artifact_bytes
artifact_budget_mib=$SMOKE_ARTIFACT_BUDGET_MIB
build_time_budget_seconds=$SMOKE_BUILD_TIME_BUDGET
boot_time_budget_seconds=$SMOKE_BOOT_TIME_BUDGET
kvm_boot_time_budget_seconds=$SMOKE_KVM_BOOT_TIME_BUDGET
kernel_artifact_sha256=$kernel_sha
initramfs_artifact_sha256=$initramfs_sha
EOF

ok "smoke kernel: out/smoke/$SMOKE_KERNEL_NAME ($kernel_bytes bytes)"
ok "smoke initramfs: out/smoke/$SMOKE_INITRAMFS_NAME ($initramfs_bytes bytes)"
ok "smoke artifact total: $artifact_bytes bytes (budget ${SMOKE_ARTIFACT_BUDGET_MIB} MiB)"
ok "smoke manifest: out/smoke/$SMOKE_MANIFEST"
