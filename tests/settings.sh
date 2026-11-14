#!/usr/bin/env bash
# Mobile settings checks.
#
# Static checks always run. When Quickshell is available the script also runs
# the navigation/validation/persistence self-test against a throwaway
# shell.json, then renders every settings page at both reference resolutions
# and a dark-palette pass. No Wi-Fi radio, audio device or backlight is touched:
# the render/self-test runs in PADILHA_SHELL_DEMO mode and the self-test asserts
# that SettingsStore made zero NetworkManager writes.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
fail=0

log() { printf '%s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

log "== settings static checks =="
if python3 tests/settings/check_settings.py; then
  ok "settings files, config keys and command policy"
else
  bad "settings static checks"
fi

if ! command -v quickshell >/dev/null 2>&1; then
  log "skip Quickshell settings checks (quickshell not installed)"
  [ "$fail" -eq 0 ]
  exit
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/padilha-settings-test.XXXXXX")
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

light="$ROOT/shell/palettes/padilha-light.json"
dark="$ROOT/tests/shell/fixtures/padilha-dark.json"
config="$tmp/config/shell.json"
mkdir -p "$tmp/config"
cat >"$config" <<'EOF'
{
    "appearance": {
        "transparency": {
            "enabled": false
        }
    },
    "existing": {
        "keep": true
    }
}
EOF

log "== navigation, validation and persistence =="
mkdir -p "$tmp/selftest-run"
chmod 700 "$tmp/selftest-run"
set +e
QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
  XDG_RUNTIME_DIR="$tmp/selftest-run" \
  PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SELFTEST=1 \
  PADILHA_SETTINGS_SELFTEST=1 PADILHA_SETTINGS_WRITE=1 \
  PADILHA_SETTINGS_CONFIG="$config" \
  PADILHA_SCHEME="$light" \
  timeout 45s quickshell -p "$ROOT/shell" --no-color >"$tmp/selftest.log" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ] || ! grep -q 'PADILHA_SHELL_SELFTEST_PASS' "$tmp/selftest.log"; then
  grep -E 'selftest|SELFTEST|ERROR|WARN scene|TypeError|Cannot assign' "$tmp/selftest.log" >&2 ||
    cat "$tmp/selftest.log" >&2
  bad "settings self-test rc=$rc"
elif grep -qE 'WARN scene|TypeError|Cannot assign|Property value set multiple times' "$tmp/selftest.log"; then
  grep -E 'WARN scene|TypeError|Cannot assign|Property value' "$tmp/selftest.log" >&2
  bad "settings self-test logged QML errors"
elif ! grep -q 'ok selftest settings-navigation' "$tmp/selftest.log"; then
  bad "settings navigation checks did not run"
elif ! grep -q 'ok selftest settings-validation' "$tmp/selftest.log"; then
  bad "settings validation checks did not run"
elif ! grep -q 'ok selftest settings-pages' "$tmp/selftest.log"; then
  bad "settings page catalogue checks did not run"
elif ! grep -q 'ok selftest settings-touch-floor' "$tmp/selftest.log"; then
  bad "settings touch-floor checks did not run"
elif ! grep -q 'ok selftest settings-scale-applied' "$tmp/selftest.log"; then
  bad "settings scale was not applied to the shell"
elif ! grep -q 'ok selftest settings-persistence' "$tmp/selftest.log"; then
  bad "settings persistence check did not run"
elif ! grep -q 'ok selftest settings-network-untouched' "$tmp/selftest.log"; then
  bad "settings self-test touched the network"
else
  ok "settings navigation, validation, touch floor and demo network guard"
fi

if python3 tests/settings/check_settings.py --config "$config"; then
  ok "settings persisted to the existing Padilha config"
else
  bad "settings persistence"
fi

shot() {
  local label=$1 size=$2 page=$3 scheme=$4 minimum=${5:-8}
  local image="$tmp/$label.png"
  local out="$tmp/$label.log"
  local width=${size%x*}
  local height=${size#*x}
  mkdir -p "$tmp/run-$label"
  chmod 700 "$tmp/run-$label"

  set +e
  QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
    XDG_RUNTIME_DIR="$tmp/run-$label" \
    PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SIZE="$size" \
    PADILHA_SHELL_SURFACE=settings PADILHA_SHELL_SETTINGS_PAGE="$page" \
    PADILHA_SCHEME="$scheme" PADILHA_SHELL_GRAB="$image" \
    timeout 45s quickshell -p "$ROOT/shell" --no-color >"$out" 2>&1
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ] || ! grep -q 'PADILHA_SHELL_GRAB_SAVED true' "$out"; then
    grep -E 'ERROR|WARN scene|TypeError|Cannot assign|GRAB' "$out" >&2 || cat "$out" >&2
    bad "render $label rc=$rc"
    return
  fi
  if grep -qE 'WARN scene|TypeError|Cannot assign|Property value set multiple times|ERROR: Failed|ERROR:   caused by' "$out"; then
    grep -E 'WARN scene|TypeError|Cannot assign|Property value|ERROR' "$out" >&2
    bad "render $label logged QML errors"
    return
  fi
  if python3 tests/shell/check_png.py "$image" "$width" "$height" "$minimum"; then
    ok "render $label"
  else
    bad "render $label PNG check"
  fi
}

log "== settings page renders =="
for size in 720x1280 1280x720; do
  for page in index network display sound battery language about; do
    shot "settings-$page-$size" "$size" "$page" "$light"
  done
done

log "== settings dark palette =="
for page in index network display sound battery language about; do
  shot "settings-dark-$page-720x1280" 720x1280 "$page" "$dark" 8
done
shot "settings-dark-display-1280x720" 1280x720 display "$dark" 8

if [ "$fail" -eq 0 ]; then
  log "all settings checks passed"
fi
[ "$fail" -eq 0 ]
