#!/usr/bin/env bash
# Build the Maria Padilha Mobile QEMU image.
#
# The script wraps a pinned pmbootstrap and a pinned pmaports checkout. It
# never partitions, flashes or writes to a block device. Full image creation
# uses pmbootstrap's chroot/mount helpers, which need sudo/doas on the host;
# --check and --dry-run are unprivileged and are what CI runs.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
. "$ROOT/scripts/lib.sh"

CHECK_ONLY=false
DRY_RUN=false
BOOT=false
DEVICE_OVERRIDE=""
export DEVICE_OVERRIDE

usage() {
  cat <<'EOF'
Usage: scripts/build.sh [options]

Options:
  --check          validate config, files, shell scripts, secrets and checksum
  --dry-run        run --check, then print the pinned build plan without network
  --boot           boot the resulting image with QEMU after building
  --device NAME    select devices/NAME/device.conf (default: qemu-aarch64)
  -h, --help       show this help

The default target is qemu-aarch64. Physical devices are documented but not
built or flashed by this milestone.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=true ;;
    --dry-run) DRY_RUN=true ;;
    --boot) BOOT=true ;;
    --device)
      [ "$#" -ge 2 ] || die "--device needs a name"
      DEVICE_OVERRIDE="$2"
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

if [ "$CHECK_ONLY" = true ]; then
  run_static_checks
  log "build scaffold check passed"
  exit 0
fi

if [ "$DRY_RUN" = true ]; then
  run_static_checks
  PMAPORTS_DIR="$TOOLCHAIN_DIR/pmaports"
  PMBOOTSTRAP_DIR="$TOOLCHAIN_DIR/pmbootstrap"
  log "would fetch pmbootstrap $PMBOOTSTRAP_VERSION ($PMBOOTSTRAP_COMMIT)"
  log "would fetch pmaports $PMAPORTS_COMMIT"
  log "would install: $DEVICE ($DEVICE_ARCH, $UI, $INIT_SYSTEM)"
  log "would install keyboard: $KEYBOARD_BACKEND ($KEYBOARD_PACKAGE)"
  log "would install power packages: $POWER_PACKAGES"
  log "would install modem packages: $MODEM_PACKAGES (telephony backend: $MODEM_BACKEND)"
  log "would stage power policy: sleep, logind, charge-threshold oneshot, udev rule"
  log "would write image: out/$IMAGE_NAME"
  log "dry run complete; no network or privileged command used"
  exit 0
fi

require_not_root
require_command git
require_command python3
require_command sha256sum
require_command find
require_command xargs

if [ "$BOOT" = true ]; then
  check_qemu_binary
fi

run_static_checks

if [ "$DEVICE_PHYSICAL" = "true" ]; then
  die "physical target '$DEVICE' is out of scope; only the QEMU target is buildable in M1"
fi

if ! command -v sudo >/dev/null 2>&1 && ! command -v doas >/dev/null 2>&1; then
  die "pmbootstrap needs sudo or doas for chroot/mount operations; run the full build on a builder that provides one"
fi

prepare_build_dirs() {
  mkdir -p -- "$BUILD_ROOT" "$PMB_WORK" "$TOOLCHAIN_DIR" "$OUT_DIR" ||
    die "cannot create build directories under $ROOT"
  case "$(cd "$BUILD_ROOT" && pwd -P)" in
    "$ROOT"/.scratch/*) ;;
    *) die "resolved BUILD_ROOT escaped $ROOT/.scratch" ;;
  esac
  ok "build directories are inside $ROOT/.scratch"
}

fetch_checkout() {
  local name="$1"
  local repo="$2"
  local commit="$3"
  local dest="$4"

  case "$dest" in
    "$TOOLCHAIN_DIR"/*) ;;
    *) die "refusing to manage a checkout outside $TOOLCHAIN_DIR: $dest" ;;
  esac

  if [ -d "$dest/.git" ] &&
    [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)" = "$commit" ]; then
    ok "$name already at $commit"
    return 0
  fi

  rm -rf -- "$dest" || die "cannot refresh $dest"
  mkdir -p -- "$(dirname -- "$dest")" || die "cannot create $dest parent"
  git init --quiet "$dest" || die "cannot init $dest"
  git -C "$dest" remote add origin "$repo" || die "cannot add $name remote"
  git -C "$dest" fetch --quiet --depth 1 origin "$commit" ||
    die "cannot fetch $name commit $commit"
  git -C "$dest" checkout --quiet --detach FETCH_HEAD ||
    die "cannot check out $name $commit"

  [ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ] ||
    die "$name checkout does not match pinned commit $commit"
  ok "$name at $commit"
}

verify_pmbootstrap_version() {
  local actual
  actual=$(python3 "$PMBOOTSTRAP_DIR/pmbootstrap.py" --version 2>/dev/null | head -1) ||
    die "pinned pmbootstrap does not run (missing Python dependency?)"
  [ "$actual" = "$PMBOOTSTRAP_VERSION" ] ||
    die "pmbootstrap version is '$actual', expected '$PMBOOTSTRAP_VERSION'"
  ok "pmbootstrap reports $actual"
}

write_pmbootstrap_config() {
  mkdir -p -- "$(dirname -- "$PMB_CONFIG")" || die "cannot create pmbootstrap config dir"
  cat >"$PMB_CONFIG" <<EOF
[pmbootstrap]
aports = $PMAPORTS_DIR
boot_size = $PMB_BOOT_SIZE
build_default_device_arch = False
build_pkgs_on_install = True
ccache_size = 5G
device = $DEVICE
extra_packages = $KEYBOARD_PACKAGE $POWER_PACKAGES $MODEM_PACKAGES
extra_space = 0
hostname = maria-padilha
is_default_channel = False
jobs = $PMB_JOBS
kernel = $PMB_KERNEL
keymap = us
locale = en_US.UTF-8
mirror_alpine = $ALPINE_MIRROR
mirrors_postmarketos = $PMOS_MIRROR
qemu_redir_stdio = False
ssh_key_glob = ~/.ssh/id_*.pub
ssh_keys = False
sudo_timer = False
systemd = always
timezone = UTC
ui = $UI
ui_extras = False
user = user
work = $PMB_WORK
EOF
  chmod 0600 "$PMB_CONFIG"
  ok "pmbootstrap config: ${PMB_CONFIG#"$ROOT"/}"
}

run_pmbootstrap_install() {
  local cmd=(
    python3 "$PMBOOTSTRAP_DIR/pmbootstrap.py"
    --config "$PMB_CONFIG"
    --aports "$PMAPORTS_DIR"
    --work "$PMB_WORK"
    --assume-yes
    --jobs "$PMB_JOBS"
    install
    --no-split
    --no-sshd
    --password "$PMB_DUMMY_PASSWORD"
    --filesystem ext4
  )
  log "running: ${cmd[*]}"
  "${cmd[@]}"
}

export_image() {
  local export_dir="$BUILD_ROOT/export"
  local src

  case "$export_dir" in
    "$BUILD_ROOT"/export) ;;
    *) die "refusing to clear unexpected export path: $export_dir" ;;
  esac
  rm -rf -- "$export_dir" || die "cannot clear $export_dir"
  mkdir -p -- "$export_dir" || die "cannot create $export_dir"

  python3 "$PMBOOTSTRAP_DIR/pmbootstrap.py" \
    --config "$PMB_CONFIG" \
    --aports "$PMAPORTS_DIR" \
    --work "$PMB_WORK" \
    export "$export_dir" --no-install ||
    die "pmbootstrap export failed"

  src="$export_dir/${DEVICE}.img"
  if [ ! -e "$src" ]; then
    src=$(find "$export_dir" -maxdepth 1 -type l -name "${DEVICE}*.img" -print -quit)
  fi
  [ -n "$src" ] && [ -e "$src" ] ||
    die "pmbootstrap did not export a ${DEVICE} image"

  cp -Lf -- "$src" "$OUT_DIR/$IMAGE_NAME" || die "cannot copy image into out/"
  chmod 0644 "$OUT_DIR/$IMAGE_NAME"
  checksum_image
}

prepare_build_dirs
PMAPORTS_DIR="$TOOLCHAIN_DIR/pmaports"
PMBOOTSTRAP_DIR="$TOOLCHAIN_DIR/pmbootstrap"

fetch_checkout "pmbootstrap" "$PMBOOTSTRAP_REPO" "$PMBOOTSTRAP_COMMIT" "$PMBOOTSTRAP_DIR"
fetch_checkout "pmaports" "$PMAPORTS_REPO" "$PMAPORTS_COMMIT" "$PMAPORTS_DIR"
verify_pmbootstrap_version
write_pmbootstrap_config

run_pmbootstrap_install
export_image

if [ "$BOOT" = true ]; then
  "$ROOT/scripts/run-qemu.sh"
fi

log "build complete: out/$IMAGE_NAME"
log "checksum:      out/$IMAGE_NAME.sha256"
