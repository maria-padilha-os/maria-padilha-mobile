#!/usr/bin/env bash
# On-screen keyboard config, layout, privacy and installer checks.
#
# These checks never start Squeekboard, a compositor, QEMU or a privileged
# command. They validate the files that the QEMU manual checklist exercises.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
fail=0

log() { printf '%s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

check_text() {
  local file=$1 needle=$2 label=$3
  if grep -qF -- "$needle" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

log "== keyboard decision and docs =="
adr=docs/adr/0002-on-screen-keyboard.md
if [ -s "$adr" ]; then
  ok "$adr"
  check_text "$adr" "## Decision" "ADR has a decision"
  check_text "$adr" "## Options considered" "ADR compares options"
  check_text "$adr" "Squeekboard" "ADR documents Squeekboard"
  check_text "$adr" "Maliit" "ADR documents Maliit"
  check_text "$adr" "text-input" "ADR covers the text-input protocol"
  check_text "$adr" "terminal" "ADR covers terminal layouts"
  check_text "$adr" "URL" "ADR covers URL layouts"
  check_text "$adr" "password" "ADR covers password fields"
  check_text "$adr" "## Consequences" "ADR records consequences"
else
  bad "$adr missing"
fi

for doc in docs/keyboard.md docs/qemu-keyboard-checklist.md; do
  if [ -s "$doc" ]; then ok "$doc"; else bad "$doc missing"; fi
done
check_text docs/qemu-keyboard-checklist.md "# Manual QEMU keyboard checklist" "checklist title"
check_text docs/qemu-keyboard-checklist.md "portrait" "checklist covers portrait"
check_text docs/qemu-keyboard-checklist.md "landscape" "checklist covers landscape"
check_text docs/qemu-keyboard-checklist.md "Terminal" "checklist covers terminal"
check_text docs/qemu-keyboard-checklist.md "URL" "checklist covers URL"
check_text docs/qemu-keyboard-checklist.md "Password" "checklist covers password"
check_text docs/qemu-keyboard-checklist.md "No physical-device claim" "checklist refuses hardware claims"

for needle in "docs/adr/0002-on-screen-keyboard.md" "docs/keyboard.md" "docs/qemu-keyboard-checklist.md" "PADILHA_SHELL_OSK"; do
  check_text README.md "$needle" "README links/keyboard hook: $needle"
done
check_text shell/README.md "KeyboardPanel.qml" "shell notes map the keyboard panel"
check_text shell/README.md "PADILHA_SHELL_OSK" "shell notes document the OSK hook"

log "== keyboard config and layouts =="
if python3 tests/keyboard/check_layouts.py; then
  ok "layout and privacy validator"
else
  bad "layout and privacy validator"
fi

# shellcheck source=/dev/null
. "$ROOT/config/keyboard/keyboard.conf"
[ "$KEYBOARD_BACKEND" = "squeekboard" ] &&
  ok "backend is squeekboard" || bad "backend is not squeekboard"
[ "$KEYBOARD_PACKAGE" = "squeekboard" ] &&
  ok "package is squeekboard" || bad "package is not squeekboard"
[ "$KEYBOARD_STORE_TYPED_TEXT" = "false" ] &&
  ok "typed text is not stored" || bad "typed text storage is enabled"
[ "$KEYBOARD_LOG_TYPED_TEXT" = "false" ] &&
  ok "typed text is not logged" || bad "typed text logging is enabled"

for relative in \
  "$KEYBOARD_PRIMARY_LAYOUT.yaml" \
  "$KEYBOARD_WIDE_LAYOUT.yaml" \
  "$KEYBOARD_TERMINAL_LAYOUT.yaml" \
  "$KEYBOARD_TERMINAL_WIDE_LAYOUT.yaml" \
  "$KEYBOARD_URL_LAYOUT.yaml" \
  "$KEYBOARD_URL_WIDE_LAYOUT.yaml" \
  "$KEYBOARD_PIN_LAYOUT.yaml" \
  "$KEYBOARD_PIN_WIDE_LAYOUT.yaml"; do
  if [ -s "$KEYBOARD_LAYOUT_DIR/$relative" ]; then
    ok "layout $relative"
  else
    bad "layout $relative missing"
  fi
done

log "== unprivileged installer =="
if [ -x scripts/install-squeekboard.sh ]; then
  ok "installer is executable"
else
  bad "installer is not executable"
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/padilha-keyboard-test.XXXXXX")
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT
if scripts/install-squeekboard.sh --dest "$tmp" >"$tmp/install.log" 2>&1; then
  ok "installer copies layouts to a user directory"
else
  cat "$tmp/install.log" >&2
  bad "installer failed"
fi
for relative in us.yaml us_wide.yaml terminal/us.yaml url/us.yaml pin/us.yaml; do
  if [ -s "$tmp/$relative" ]; then ok "installed $relative"; else bad "installed $relative missing"; fi
done
if scripts/install-squeekboard.sh --dest "$tmp" --dry-run >"$tmp/dry.log" 2>&1 &&
  grep -q "dry run complete" "$tmp/dry.log"; then
  ok "installer dry run"
else
  bad "installer dry run"
fi

if grep -RInE --binary-files=without-match \
  -e '(KEYBOARD_PACKAGE="maliit|maliit-keyboard)' \
  config scripts >/dev/null 2>&1; then
  bad "Maliit appears as a runtime keyboard dependency"
else
  ok "no Maliit runtime dependency"
fi

if [ "$fail" -eq 0 ]; then
  log "all keyboard checks passed"
fi
[ "$fail" -eq 0 ]
