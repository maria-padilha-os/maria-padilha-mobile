#!/usr/bin/env bash
# Boot the built QEMU image with the pinned pmbootstrap helper.
#
# This is the validation path for the milestone: it needs qemu-system-aarch64,
# not a phone. No block device is touched.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
. "$ROOT/scripts/lib.sh"

load_config
validate_config

[ "$DEVICE_PHYSICAL" = "false" ] ||
  die "run-qemu.sh only boots the virtual target; '$DEVICE' is physical"
[ "$DEVICE_KIND" = "virtual" ] ||
  die "run-qemu.sh only boots virtual devices"

check_qemu_binary
require_command python3

PMAPORTS_DIR="$TOOLCHAIN_DIR/pmaports"
PMBOOTSTRAP_DIR="$TOOLCHAIN_DIR/pmbootstrap"

[ -f "$OUT_DIR/$IMAGE_NAME" ] ||
  die "missing out/$IMAGE_NAME; run scripts/build.sh first"
[ -f "$OUT_DIR/$IMAGE_NAME.sha256" ] ||
  die "missing out/$IMAGE_NAME.sha256; refusing to boot an unchecked image"
(cd "$OUT_DIR" && sha256sum --check --quiet "$IMAGE_NAME.sha256") ||
  die "image checksum does not match out/$IMAGE_NAME.sha256"
ok "image checksum verifies"

[ -d "$PMBOOTSTRAP_DIR/.git" ] ||
  die "missing pinned pmbootstrap checkout; run scripts/build.sh first"
[ -d "$PMAPORTS_DIR/.git" ] ||
  die "missing pinned pmaports checkout; run scripts/build.sh first"

display="${PADILHA_QEMU_DISPLAY:-$QEMU_DISPLAY}"
cmd=(
  python3 "$PMBOOTSTRAP_DIR/pmbootstrap.py"
  --config "$PMB_CONFIG"
  --aports "$PMAPORTS_DIR"
  --work "$PMB_WORK"
  qemu
  --image-size "$IMAGE_SIZE"
  --memory "$QEMU_MEMORY"
  --cpu "$QEMU_CPU"
  --display "$display"
  --audio none
  --tablet
  --no-kvm
)
if [ "$display" = "none" ]; then
  cmd+=(--no-gl)
  log "booting headless; set PADILHA_QEMU_DISPLAY=gtk for an interactive window"
fi

log "running: ${cmd[*]}"
exec "${cmd[@]}" "$@"
