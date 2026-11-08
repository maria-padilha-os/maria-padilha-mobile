#!/usr/bin/env bash
# Shell prototype checks.
#
# Always runs the palette/contrast checks. When Quickshell is available it also
# lints the QML, runs the shell self-test against the existing/bundled colour
# state, and renders the four surfaces at both reference resolutions through
# Qt's offscreen platform. No compositor, private window or terminal is captured.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
fail=0

log() { printf '%s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

log "== palette and contrast =="
if python3 tests/shell/palette_check.py; then
  ok "palette fixtures and contrast guard"
else
  bad "palette fixtures or contrast guard"
fi

if ! command -v quickshell >/dev/null 2>&1; then
  log "skip Quickshell checks (quickshell not installed)"
  [ "$fail" -eq 0 ]
  exit
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/padilha-shell-test.XXXXXX")
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

log "== qml lint =="
if command -v qmllint >/dev/null 2>&1; then
  import_dir=""
  if command -v qtpaths >/dev/null 2>&1; then
    import_dir=$(qtpaths --query QT_INSTALL_QML 2>/dev/null || true)
  fi
  if [ -z "$import_dir" ] && [ -d /usr/lib/qt6/qml ]; then
    import_dir=/usr/lib/qt6/qml
  fi
  lint_args=()
  [ -n "$import_dir" ] && lint_args+=(-I "$import_dir")
  mapfile -t qml_files < <(find shell -type f -name '*.qml' | LC_ALL=C sort)
  if qmllint "${lint_args[@]}" "${qml_files[@]}" >"$tmp/qmllint.log" 2>&1; then
    if [ -s "$tmp/qmllint.log" ]; then
      cat "$tmp/qmllint.log" >&2
      bad "qmllint reported warnings"
    else
      ok "qmllint ${#qml_files[@]} files"
    fi
  else
    cat "$tmp/qmllint.log" >&2
    bad "qmllint failed"
  fi
else
  log "skip qmllint (not installed)"
fi

run_selftest() {
  local label=$1 scheme=$2
  local out="$tmp/selftest-$label.log"
  mkdir -p "$tmp/run-$label"
  chmod 700 "$tmp/run-$label"
  set +e
  QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
    XDG_RUNTIME_DIR="$tmp/run-$label" \
    PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SELFTEST=1 PADILHA_SCHEME="$scheme" \
    timeout 45s quickshell -p "$ROOT/shell" --no-color >"$out" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ] || ! grep -q 'PADILHA_SHELL_SELFTEST_PASS' "$out"; then
    grep -E 'selftest|SELFTEST|ERROR|WARN scene|TypeError|Cannot assign' "$out" >&2 || cat "$out" >&2
    bad "shell self-test ($label) rc=$rc"
  else
    ok "shell self-test ($label)"
  fi
}

log "== palette reload =="
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
if [ -f "$state_home/caelestia/scheme.json" ]; then
  run_selftest existing-padilha-state "$state_home/caelestia/scheme.json"
else
  log "skip existing-padilha-state (no $state_home/caelestia/scheme.json)"
fi
run_selftest bundled "$ROOT/shell/palettes/padilha-light.json"
run_selftest guarded-broken "$ROOT/tests/shell/fixtures/broken-light.json"
run_selftest fallback-missing "$tmp/does-not-exist/scheme.json"

privacy_selftest() {
  local secret="padilha-typed-text-${RANDOM}-$$"
  local out="$tmp/selftest-privacy.log"
  mkdir -p "$tmp/run-privacy"
  chmod 700 "$tmp/run-privacy"
  set +e
  QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
    XDG_RUNTIME_DIR="$tmp/run-privacy" \
    PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SELFTEST=1 PADILHA_SHELL_SURFACE=lock \
    PADILHA_SHELL_QUERY="$secret" PADILHA_SHELL_PIN=9876 \
    PADILHA_SCHEME="$ROOT/shell/palettes/padilha-light.json" \
    timeout 45s quickshell -p "$ROOT/shell" --no-color >"$out" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ] || ! grep -q 'PADILHA_SHELL_SELFTEST_PASS' "$out"; then
    grep -E 'selftest|SELFTEST|ERROR|WARN scene|TypeError|Cannot assign' "$out" >&2 || cat "$out" >&2
    bad "typed-text logging self-test rc=$rc"
  elif grep -qF "$secret" "$out" || grep -qF '9876' "$out"; then
    bad "typed-text logging self-test found the query or PIN in shell output"
  else
    ok "typed-text logging self-test"
  fi
}

log "== typed-text logging =="
privacy_selftest

shot() {
  local label=$1 size=$2 surface=$3 scheme=$4 pin=${5:-} osk=${6:-} purpose=${7:-}
  local image="$tmp/$label.png"
  local out="$tmp/$label.log"
  local width=${size%x*}
  local height=${size#*x}
  mkdir -p "$tmp/run-$label"
  chmod 700 "$tmp/run-$label"

  set +e
  QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
    XDG_RUNTIME_DIR="$tmp/run-$label" \
    PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SIZE="$size" PADILHA_SHELL_SURFACE="$surface" \
    PADILHA_SHELL_PIN="$pin" PADILHA_SCHEME="$scheme" PADILHA_SHELL_GRAB="$image" \
    PADILHA_SHELL_OSK="$osk" PADILHA_SHELL_KEYBOARD="${osk:+1}" \
    PADILHA_SHELL_KEYBOARD_PURPOSE="$purpose" \
    timeout 45s quickshell -p "$ROOT/shell" --no-color >"$out" 2>&1
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ] || ! grep -q 'PADILHA_SHELL_GRAB_SAVED true' "$out"; then
    grep -E 'ERROR|WARN scene|TypeError|Cannot assign|GRAB' "$out" >&2 || cat "$out" >&2
    bad "render $label rc=$rc"
    return
  fi
  if grep -qE 'WARN scene|TypeError|Cannot assign|ERROR: Failed|ERROR:   caused by' "$out"; then
    grep -E 'WARN scene|TypeError|Cannot assign|ERROR' "$out" >&2
    bad "render $label logged QML errors"
    return
  fi
  if python3 tests/shell/check_png.py "$image" "$width" "$height"; then
    ok "render $label"
  else
    bad "render $label PNG check"
  fi
}

log "== responsive renders =="
light="$ROOT/shell/palettes/padilha-light.json"
dark="$ROOT/tests/shell/fixtures/padilha-dark.json"
for surface in home launcher notifications lock; do
  pin=""
  [ "$surface" = "lock" ] && pin=1234
  shot "$surface-720x1280" 720x1280 "$surface" "$light" "$pin"
  shot "$surface-1280x720" 1280x720 "$surface" "$light" "$pin"
done
shot "home-720x1280-dark" 720x1280 home "$dark"
shot "home-1280x720-dark" 1280x720 home "$dark"

log "== fallback keyboard renders =="
for purpose in text terminal url password; do
  shot "keyboard-$purpose-720x1280" 720x1280 launcher "$light" "" inline "$purpose"
  shot "keyboard-$purpose-1280x720" 1280x720 launcher "$light" "" inline "$purpose"
done
shot "keyboard-terminal-1280x720-dark" 1280x720 launcher "$dark" "" inline terminal

if [ "$fail" -eq 0 ]; then
  log "all shell checks passed"
fi
[ "$fail" -eq 0 ]
