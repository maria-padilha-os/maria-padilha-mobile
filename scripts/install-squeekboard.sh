#!/usr/bin/env bash
# Install the Padilha Squeekboard layouts into the current user's data
# directory and, optionally, apply the Squeekboard show/hide settings.
#
# This script is unprivileged. It writes only under the destination data
# directory (by default $XDG_DATA_HOME/squeekboard/keyboards) and never calls
# sudo, pkexec, systemctl, pacman, mount or a partition tool.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
. "$ROOT/scripts/lib.sh"

DEST=""
APPLY_SETTINGS=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/install-squeekboard.sh [options]

Options:
  --dest DIR        install layouts under DIR (default: user Squeekboard data)
  --apply-settings  apply the Padilha Squeekboard gsettings (unprivileged)
  --dry-run         print what would be installed without writing
  -h, --help        show this help

The default destination is
$XDG_DATA_HOME/squeekboard/keyboards (or ~/.local/share/...). Existing files
with the same names are replaced; no other layout files are touched.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest)
      [ "$#" -ge 2 ] || die "--dest needs a directory"
      DEST="$2"
      shift
      ;;
    --apply-settings) APPLY_SETTINGS=true ;;
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

[ "$(id -u)" -ne 0 ] ||
  die "run this as the desktop user, not root; it installs into the user data directory"

KEYBOARD_CONFIG="${KEYBOARD_CONFIG:-config/keyboard/keyboard.conf}"
[ -f "$ROOT/$KEYBOARD_CONFIG" ] || die "missing $KEYBOARD_CONFIG"
# shellcheck source=/dev/null
. "$ROOT/$KEYBOARD_CONFIG"

[ "$KEYBOARD_BACKEND" = "squeekboard" ] ||
  die "keyboard backend is '$KEYBOARD_BACKEND', not squeekboard"

if [ -z "$DEST" ]; then
  data_home="${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}"
  DEST="$data_home/squeekboard/keyboards"
fi
[ -n "$DEST" ] || die "destination is empty"
case "$DEST" in
  / | "$HOME" | "$ROOT") die "refusing to install layouts into $DEST" ;;
esac

layouts=(
  "$KEYBOARD_PRIMARY_LAYOUT.yaml"
  "$KEYBOARD_WIDE_LAYOUT.yaml"
  "$KEYBOARD_TERMINAL_LAYOUT.yaml"
  "$KEYBOARD_TERMINAL_WIDE_LAYOUT.yaml"
  "$KEYBOARD_URL_LAYOUT.yaml"
  "$KEYBOARD_URL_WIDE_LAYOUT.yaml"
  "$KEYBOARD_PIN_LAYOUT.yaml"
  "$KEYBOARD_PIN_WIDE_LAYOUT.yaml"
)

for relative in "${layouts[@]}"; do
  src="$ROOT/$KEYBOARD_LAYOUT_DIR/$relative"
  dst="$DEST/$relative"
  [ -f "$src" ] || die "missing layout: ${src#"$ROOT"/}"
  if [ "$DRY_RUN" = true ]; then
    log "would install ${src#"$ROOT"/} -> $dst"
    continue
  fi
  install -d -m 700 -- "$(dirname -- "$dst")" ||
    die "cannot create $(dirname -- "$dst")"
  install -m 600 -- "$src" "$dst" ||
    die "cannot install $relative"
  ok "installed $relative"
done

if [ "$APPLY_SETTINGS" = true ]; then
  command -v gsettings >/dev/null 2>&1 ||
    die "gsettings is required for --apply-settings"

  if gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.desktop.a11y.applications'; then
    gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled \
      "$KEYBOARD_SHOW_ON_FOCUS" ||
      die "cannot enable the screen keyboard setting"
    ok "screen keyboard enabled"
  else
    log "skip screen-keyboard setting (GNOME a11y schema not installed)"
  fi

  if gsettings list-schemas 2>/dev/null | grep -qx 'sm.puri.Squeekboard'; then
    gsettings set sm.puri.Squeekboard scale-in-horizontal-screen-orientation \
      "$KEYBOARD_SCALE_PORTRAIT" ||
      die "cannot set portrait Squeekboard scale"
    gsettings set sm.puri.Squeekboard scale-in-vertical-screen-orientation \
      "$KEYBOARD_SCALE_LANDSCAPE" ||
      die "cannot set landscape Squeekboard scale"
    gsettings set sm.puri.Squeekboard layout-shape-changes-to-fit-panel \
      "$KEYBOARD_FIT_PANEL" ||
      die "cannot set Squeekboard fit-panel policy"
    ok "Squeekboard orientation settings applied"
  else
    log "skip Squeekboard gsettings (sm.puri.Squeekboard schema not installed)"
  fi
fi

if [ "$DRY_RUN" = true ]; then
  log "dry run complete; no files or settings changed"
else
  log "Squeekboard layouts installed in $DEST"
  log "restart Squeekboard or re-open a text field to pick up the layouts"
fi
