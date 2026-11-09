#!/usr/bin/env bash
# Stage the Maria Padilha power configuration into a directory tree.
#
# This script is unprivileged and deliberately does not install into /etc or
# /usr on the running host. It fills a staging root that an image builder (or a
# later, explicitly reviewed root step) can copy into the target rootfs.
#
# No sudo, pkexec, systemctl, pacman, mount or block-device access is used.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/power/power.conf
. "$ROOT/config/power/power.conf"

DEST="$ROOT/.scratch/power-root"
DRY_RUN=false

die() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*"
}

ok() {
  printf 'ok %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: scripts/stage-power-config.sh [options]

Options:
  --dest DIR    stage under DIR (default: .scratch/power-root)
  --dry-run     print what would be staged without writing
  -h, --help    show this help

The destination is a staging tree, not a live root. This script never writes
to /etc, /usr or /sys and never loads a service manager.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest)
      [ "$#" -ge 2 ] || die "--dest needs a directory"
      DEST="$2"
      shift
      ;;
    --dry-run) DRY_RUN=true ;;
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

[ -n "$DEST" ] || die "destination is empty"

sources=(
  "$ROOT/config/power/power.conf|0644|etc/maria-padilha/power.conf"
  "$ROOT/scripts/power-charge-thresholds.sh|0755|usr/libexec/maria-padilha/power-charge-thresholds"
  "$ROOT/scripts/power-sleep-hook.sh|0755|usr/lib/systemd/system-sleep/maria-padilha-power"
  "$ROOT/config/power/systemd/maria-padilha-charge-thresholds.service|0644|etc/systemd/system/maria-padilha-charge-thresholds.service"
  "$ROOT/config/power/systemd/sleep.conf.d/10-maria-padilha-sleep.conf|0644|etc/systemd/sleep.conf.d/10-maria-padilha-sleep.conf"
  "$ROOT/config/power/systemd/logind.conf.d/10-maria-padilha-power.conf|0644|etc/systemd/logind.conf.d/10-maria-padilha-power.conf"
  "$ROOT/config/power/udev/90-maria-padilha-charge-thresholds.rules|0644|etc/udev/rules.d/90-maria-padilha-charge-thresholds.rules"
  "$ROOT/docs/power.md|0644|usr/share/doc/maria-padilha-mobile/power.md"
)

for entry in "${sources[@]}"; do
  src=${entry%%|*}
  rest=${entry#*|}
  mode=${rest%%|*}
  relative=${rest#*|}
  [ -f "$src" ] || die "missing source: ${src#"$ROOT"/}"
done

if [ "$DRY_RUN" = true ]; then
  log "would stage power configuration under $DEST"
  for entry in "${sources[@]}"; do
    src=${entry%%|*}
    rest=${entry#*|}
    mode=${rest%%|*}
    relative=${rest#*|}
    log "would install ${src#"$ROOT"/} -> $relative (mode $mode)"
  done
  log "would enable $POWER_CHARGE_THRESHOLD_SERVICE for multi-user.target"
  log "dry run complete; no files changed"
  exit 0
fi

mkdir -p -- "$DEST" || die "cannot create $DEST"
DEST_ABS=$(CDPATH='' cd -- "$DEST" && pwd -P)
case "$DEST_ABS" in
  / | "$HOME" | "$ROOT") die "refusing to stage into $DEST_ABS" ;;
esac

for entry in "${sources[@]}"; do
  src=${entry%%|*}
  rest=${entry#*|}
  mode=${rest%%|*}
  relative=${rest#*|}
  dest="$DEST_ABS/$relative"
  install -d -m 0755 -- "$(dirname -- "$dest")" ||
    die "cannot create $(dirname -- "$dest")"
  install -m "$mode" -- "$src" "$dest" ||
    die "cannot install $relative"
  ok "staged $relative"
done

wants_dir="$DEST_ABS/etc/systemd/system/multi-user.target.wants"
install -d -m 0755 -- "$wants_dir" || die "cannot create $wants_dir"
ln -sfn "../$POWER_CHARGE_THRESHOLD_SERVICE" "$wants_dir/$POWER_CHARGE_THRESHOLD_SERVICE" ||
  die "cannot enable $POWER_CHARGE_THRESHOLD_SERVICE in the staging tree"
ok "enabled $POWER_CHARGE_THRESHOLD_SERVICE for multi-user.target"

log "power configuration staged in $DEST_ABS"
log "the image builder must copy this tree into the target rootfs; this script did not touch the live system"
