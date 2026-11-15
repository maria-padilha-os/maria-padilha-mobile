#!/usr/bin/env bash
# Read-only preflight for a manual SD-card flash.
#
# This script NEVER flashes, partitions, formats, mounts, unmounts or writes to
# a device. It validates the image checksum and the target device path, then
# prints what a human should review before following docs/flashing.md.
#
# No write-capable mode exists. A green preflight is not a support claim and
# is not an invitation to automate the write step.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
. "$ROOT/scripts/lib.sh"

MODE="both"
DEVICE_NAME=""
IMAGE=""
TARGET=""
STRICT_SUPPORT=false

usage() {
  cat <<'EOF'
Usage: scripts/flash-check.sh --device NAME [options]

Read-only preflight for a manual flash. It validates the image and its SHA-256
manifest, validates that the target is a whole, removable, unmounted block
device, and prints a review summary. It never writes anything.

Required:
  --device NAME     devices/NAME/device.conf to check against

Image and target:
  --image PATH      image to check (default: out/<device image name>)
  --target PATH     whole-disk device node, for example /dev/sdX
  --image-only      check only the image and manifest
  --target-only     check only the target device path

Policy:
  --strict-support  exit 2 unless the device status is `supported`
  -h, --help        show this help

Exit status:
  0  requested safety checks passed (no write performed)
  1  a safety check failed
  2  usage error, or --strict-support rejected a non-supported device

The script refuses to run as root. It contains no privileged or device-write
path and never invokes a flasher or partition tool.
EOF
}

usage_error() {
  printf 'FAIL %s\n' "$*" >&2
  usage >&2
  exit 2
}

warn() {
  printf 'WARNING %s\n' "$*" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      [ "$#" -ge 2 ] || usage_error "--device needs a device name"
      DEVICE_NAME=$2
      shift
      ;;
    --image)
      [ "$#" -ge 2 ] || usage_error "--image needs a path"
      IMAGE=$2
      shift
      ;;
    --target)
      [ "$#" -ge 2 ] || usage_error "--target needs a path"
      TARGET=$2
      shift
      ;;
    --image-only)
      [ "$MODE" = "both" ] || usage_error "choose at most one of --image-only and --target-only"
      MODE="image"
      ;;
    --target-only)
      [ "$MODE" = "both" ] || usage_error "choose at most one of --image-only and --target-only"
      MODE="target"
      ;;
    --strict-support) STRICT_SUPPORT=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown option: $1"
      ;;
  esac
  shift
done

[ -n "$DEVICE_NAME" ] || usage_error "--device is required"
[ "$(id -u)" -ne 0 ] ||
  die "run the preflight as an unprivileged user; it never needs root"

case "$MODE" in
  image)
    [ -z "$TARGET" ] || usage_error "--image-only cannot be combined with --target"
    ;;
  target)
    [ -z "$IMAGE" ] || usage_error "--target-only cannot be combined with --image"
    ;;
  both)
    [ -n "$TARGET" ] || usage_error "--target is required unless --image-only or --target-only is used"
    ;;
esac

DEVICE_OVERRIDE="$DEVICE_NAME"
export DEVICE_OVERRIDE
load_config

# shellcheck source=../config/flashing.conf
. "$ROOT/config/flashing.conf"

validate_flash_policy() {
  [ "$FLASHING_CONFIG_VERSION" = "1" ] ||
    die "unsupported flashing config version: $FLASHING_CONFIG_VERSION"
  [ "$FLASHING_MODE" = "manual-check-only" ] ||
    die "flashing mode must stay manual-check-only"
  [ "$FLASHING_AUTOMATIC" = "false" ] ||
    die "automatic flashing must stay disabled"
  [ "$FLASHING_REQUIRE_CHECKSUM" = "true" ] ||
    die "the preflight must require an image checksum"
  [ "$FLASHING_TARGET_PREFIX" = "/dev/" ] ||
    die "the target prefix must stay /dev/"
  [ "$FLASHING_REQUIRE_BLOCK_DEVICE" = "true" ] &&
    [ "$FLASHING_REQUIRE_WHOLE_DISK" = "true" ] &&
    [ "$FLASHING_REQUIRE_REMOVABLE" = "true" ] ||
    die "target block/whole-disk/removable checks must stay enabled"
  [ "$FLASHING_REFUSE_READ_ONLY" = "true" ] &&
    [ "$FLASHING_REFUSE_MOUNTED" = "true" ] &&
    [ "$FLASHING_REFUSE_SWAP" = "true" ] ||
    die "read-only/mounted/swap target checks must stay enabled"
  [[ "$FLASHING_TARGET_MARGIN_MIB" =~ ^[0-9]+$ ]] ||
    die "FLASHING_TARGET_MARGIN_MIB must be an integer"
  [[ "$FLASHING_ALLOWED_TARGET_REGEX" =~ ^\^/dev/ ]] ||
    die "the target regex must be anchored under /dev/"
}

validate_flash_policy

# The build config gate is used as a consistency check: the device config must
# still describe an aarch64 Phosh target before its flashing status is trusted.
validate_config

suffix=${DEVICE//-/_}
status_var="FLASH_STATUS_$suffix"
media_var="FLASH_MEDIA_$suffix"
transport_var="FLASH_TRANSPORT_$suffix"
bootloader_var="FLASH_BOOTLOADER_$suffix"
recovery_var="FLASH_RECOVERY_$suffix"

status="${!status_var:-}"
media="${!media_var:-unknown}"
transport="${!transport_var:-unknown}"
bootloader="${!bootloader_var:-unknown}"
recovery="${!recovery_var:-unknown}"

[ -n "$status" ] || die "device '$DEVICE' is not in the flashing matrix (config/flashing.conf)"
case "$status" in
  virtual-only)
    die "'$DEVICE' is a virtual target and is never flashed; use scripts/run-qemu.sh"
    ;;
  supported | bring-up | unsupported) ;;
  *)
    die "unknown flashing status '$status' for '$DEVICE'"
    ;;
esac

if [ "$status" = "unsupported" ]; then
  die "'$DEVICE' is explicitly unsupported and must not be flashed"
fi

if [ "$status" = "bring-up" ]; then
  warn "'$DEVICE' is a documented bring-up candidate, not a supported release target."
  warn "Use a spare unit with a verified backup. Do not publish or redistribute this image."
fi

if [ "$STRICT_SUPPORT" = true ] && [ "$status" != "supported" ]; then
  printf 'FAIL strict support gate: %s has status %s, not supported\n' "$DEVICE" "$status" >&2
  exit 2
fi

validate_image() {
  local image=$1
  local image_real image_dir_real manifest
  local expected_sha manifest_name actual_sha
  local manifest_lines manifest_fields image_size

  [ -e "$image" ] || die "image not found: $image"
  [ ! -L "$image" ] || die "image must not be a symlink; use the real file"
  [ -f "$image" ] || die "image is not a regular file: $image"
  [ -r "$image" ] || die "image is not readable: $image"

  image_real=$(realpath -e -- "$image") || die "cannot resolve image path: $image"
  [ -d "$FLASHING_IMAGE_DIR" ] || die "image directory is missing: $FLASHING_IMAGE_DIR"
  image_dir_real=$(realpath -e -- "$FLASHING_IMAGE_DIR") ||
    die "cannot resolve image directory: $FLASHING_IMAGE_DIR"
  case "$image_real" in
    "$image_dir_real"/*) ;;
    *) die "image must stay under $image_dir_real (got $image_real)" ;;
  esac

  image_size=$(stat -c %s -- "$image_real") || die "cannot read image size: $image_real"
  [[ "$image_size" =~ ^[0-9]+$ ]] && [ "$image_size" -gt 0 ] ||
    die "image is empty or has an invalid size: $image_real"

  manifest="$image_real$FLASHING_MANIFEST_SUFFIX"
  [ -e "$manifest" ] || die "missing checksum manifest: $manifest"
  [ ! -L "$manifest" ] || die "checksum manifest must not be a symlink: $manifest"
  [ -f "$manifest" ] || die "checksum manifest is not a regular file: $manifest"
  [ -r "$manifest" ] || die "checksum manifest is not readable: $manifest"

  manifest_lines=$(wc -l <"$manifest" | tr -d '[:space:]')
  [ "$manifest_lines" = "1" ] ||
    die "checksum manifest must contain exactly one line: $manifest"
  manifest_fields=$(awk 'NR == 1 { print NF }' "$manifest")
  [ "$manifest_fields" = "2" ] ||
    die "checksum manifest must be '<sha256>  <filename>': $manifest"

  expected_sha=$(awk 'NR == 1 { print $1 }' "$manifest")
  manifest_name=$(awk 'NR == 1 { print $2 }' "$manifest")
  manifest_name=${manifest_name#\*}
  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] ||
    die "checksum manifest does not contain a lowercase SHA-256: $manifest"
  [ "$manifest_name" = "$(basename -- "$image_real")" ] ||
    die "checksum manifest names '$manifest_name', expected '$(basename -- "$image_real")'"

  actual_sha=$(sha256sum -- "$image_real" | awk '{ print $1 }') ||
    die "cannot checksum image: $image_real"
  [ "$actual_sha" = "$expected_sha" ] ||
    die "image checksum mismatch: $actual_sha != $expected_sha"

  validated_image=$image_real
  validated_image_size=$image_size
  validated_image_sha=$actual_sha
}

validate_target() {
  local target=$1
  local target_real dev_type rm_flag ro_flag target_size target_size_human
  local majmin margin

  case "$target" in
    "$FLASHING_TARGET_PREFIX"*) ;;
    *) die "target must be under $FLASHING_TARGET_PREFIX (got $target)" ;;
  esac
  [ -e "$target" ] || die "target does not exist: $target"
  [ ! -L "$target" ] ||
    die "target must be a canonical device node, not a symlink: $target"
  target_real=$(realpath -e -- "$target") || die "cannot resolve target path: $target"

  case "$target_real" in
    "$FLASHING_TARGET_PREFIX"*) ;;
    *) die "resolved target escaped $FLASHING_TARGET_PREFIX: $target_real" ;;
  esac
  [[ "$target_real" =~ $FLASHING_ALLOWED_TARGET_REGEX ]] ||
    die "target is not an allowed whole-disk node: $target_real"
  [ -b "$target_real" ] || die "target is not a block device: $target_real"

  command -v lsblk >/dev/null 2>&1 ||
    die "lsblk is required to validate the target device"

  dev_type=$(lsblk -dn -o TYPE -- "$target_real" 2>/dev/null | head -1 | tr -d '[:space:]')
  [ "$dev_type" = "disk" ] ||
    die "target must be a whole disk, not a partition or virtual node: $target_real"

  rm_flag=$(lsblk -dn -o RM -- "$target_real" 2>/dev/null | head -1 | tr -d '[:space:]')
  [ "$rm_flag" = "1" ] ||
    die "target is not reported as removable (RM=${rm_flag:-?}); refusing to treat a fixed disk as a flash target"

  ro_flag=$(lsblk -dn -o RO -- "$target_real" 2>/dev/null | head -1 | tr -d '[:space:]')
  [ "$ro_flag" = "0" ] ||
    die "target is read-only (RO=${ro_flag:-?}); check the card's write-protect switch"

  majmin=$(lsblk -dn -o MAJ:MIN -- "$target_real" 2>/dev/null | head -1 | tr -d '[:space:]')
  [[ "$majmin" =~ ^[0-9]+:[0-9]+$ ]] ||
    die "cannot determine target major:minor: $target_real"

  target_size=$(lsblk -bdn -o SIZE -- "$target_real" 2>/dev/null | head -1 | tr -d '[:space:]')
  [[ "$target_size" =~ ^[0-9]+$ ]] && [ "$target_size" -gt 0 ] ||
    die "cannot determine target size: $target_real"

  if [ -n "${validated_image_size:-}" ]; then
    margin=$((FLASHING_TARGET_MARGIN_MIB * 1024 * 1024))
    [ "$target_size" -ge $((validated_image_size + margin)) ] ||
      die "target is too small: $target_size bytes, image needs $validated_image_size plus ${FLASHING_TARGET_MARGIN_MIB} MiB"
  fi

  while IFS= read -r device_majmin; do
    [ -n "$device_majmin" ] || continue
    if awk -v mm="$device_majmin" '$3 == mm { found = 1 } END { exit(found ? 0 : 1) }' \
      /proc/self/mountinfo; then
      die "target or a partition of it is mounted (device $device_majmin); unmount it first"
    fi
  done < <(lsblk -nr -o MAJ:MIN -- "$target_real")

  [ -r /proc/swaps ] || die "cannot check swap state: /proc/swaps is not readable"
  while IFS= read -r device_path; do
    [ -n "$device_path" ] || continue
    if awk -v path="$device_path" 'NR > 1 && $1 == path { found = 1 } END { exit(found ? 0 : 1) }' \
      /proc/swaps; then
      die "target or a partition of it is in use as swap: $device_path"
    fi
  done < <(lsblk -nr -o PATH -- "$target_real")

  target_size_human=$(lsblk -dn -o SIZE -- "$target_real" 2>/dev/null | head -1 | tr -d '[:space:]')
  target_model=$(lsblk -dn -o MODEL -- "$target_real" 2>/dev/null | head -1 | sed 's/^ *//; s/ *$//')
  target_tran=$(lsblk -dn -o TRAN -- "$target_real" 2>/dev/null | head -1 | tr -d '[:space:]')

  validated_target=$target_real
  validated_target_size=$target_size
  validated_target_size_human=$target_size_human
  validated_target_model=$target_model
  validated_target_transport=$target_tran
}

log "== flashing preflight (read-only) =="
ok "device: $DEVICE ($status, media: $media, transport: $transport)"
log "bootloader: $bootloader"
log "recovery:   $recovery"

if [ "$MODE" = "target" ]; then
  log "image:      not checked (--target-only)"
else
  [ -n "$IMAGE" ] || IMAGE="$OUT_DIR/$IMAGE_NAME"
  validate_image "$IMAGE"
  ok "image: out/$(basename -- "$validated_image") ($validated_image_size bytes)"
  ok "sha256: $validated_image_sha"
fi

if [ "$MODE" = "image" ]; then
  log "target:     not checked (--image-only)"
else
  validate_target "$TARGET"
  target_label=$validated_target
  [ -n "$validated_target_model" ] && target_label="$target_label ($validated_target_model)"
  ok "target: $target_label"
  ok "target size: $validated_target_size bytes ($validated_target_size_human), transport: ${validated_target_transport:-unknown}"
  ok "target is a whole, removable, writable, unmounted disk"
fi

log ""
log "NO WRITE WAS PERFORMED."
log "The write step is manual and is documented in $FLASHING_DOC."
log "Re-run this preflight immediately before the manual write; the image or target may change."
if [ "$status" = "bring-up" ]; then
  log "Support status: bring-up only. This is not a supported release target."
else
  log "Support status: $status"
fi
