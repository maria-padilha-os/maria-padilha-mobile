#!/usr/bin/env bash
# Camera and media-capture checks.
#
# The static checks are unprivileged. The integration checks use the emulated
# xdg-desktop-portal Camera fixture in tests/camera/ and generated test
# patterns in a temporary directory. They never open /dev/video*, never capture
# a real camera or the desktop, and never prompt the host for permission.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
fail=0

log() { printf '%s\n' "$*"; }
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

check_file() {
  local file=$1
  if [ -s "$file" ]; then ok "$file"; else bad "$file missing"; fi
}

check_text() {
  local file=$1 needle=$2 label=$3
  if grep -qF -- "$needle" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/padilha-camera-test.XXXXXX")
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

log "== camera decision and docs =="
adr=docs/adr/0004-camera-and-media-capture.md
if [ -s "$adr" ]; then
  ok "$adr"
  check_text "$adr" "## Decision" "ADR has a decision"
  check_text "$adr" "## Options considered" "ADR compares options"
  check_text "$adr" "libcamera" "ADR names libcamera"
  check_text "$adr" "PipeWire" "ADR names PipeWire"
  check_text "$adr" "xdg-desktop-portal" "ADR names the permission boundary"
  check_text "$adr" "## Consequences" "ADR records consequences"
  check_text "$adr" "## Privacy contract" "ADR records the privacy contract"
  check_text "$adr" "No real camera" "ADR refuses a real-camera claim"
  check_text "$adr" "## Sources" "ADR has sources"
else
  bad "$adr missing"
fi

for doc in docs/camera.md docs/qemu-camera-checklist.md docs/camera-supported-devices.md; do
  check_file "$doc"
done
check_text docs/camera.md "## Components" "camera docs list components"
check_text docs/camera.md "## Permission flow" "camera docs cover permissions"
check_text docs/camera.md "## Graceful states" "camera docs cover graceful states"
check_text docs/camera.md "## Test patterns" "camera docs cover generated patterns"
check_text docs/camera.md "## Privacy contract" "camera docs cover privacy"
check_text docs/camera.md "## Known limitations" "camera docs state limitations"
check_text docs/camera-supported-devices.md "# Camera supported-device note" "device note title"
check_text docs/camera-supported-devices.md "No physical device" "device note refuses a physical claim"
check_text docs/camera-supported-devices.md "QEMU" "device note covers QEMU"
check_text docs/qemu-camera-checklist.md "# Manual QEMU camera checklist" "checklist title"
check_text docs/qemu-camera-checklist.md "No real camera claim" "checklist refuses a hardware claim"
check_text docs/qemu-camera-checklist.md "generated test pattern" "checklist uses generated patterns"

for needle in \
  "docs/adr/0004-camera-and-media-capture.md" \
  "docs/camera.md" \
  "docs/qemu-camera-checklist.md" \
  "docs/camera-supported-devices.md" \
  "make camera-test" \
  "libcamera" \
  "PipeWire"; do
  check_text README.md "$needle" "README camera link/text: $needle"
done

log "== camera config =="
# shellcheck source=../config/camera/camera.conf
. "$ROOT/config/camera/camera.conf"
[ "$CAMERA_STACK" = "libcamera-pipewire-portal" ] &&
  ok "stack is libcamera-pipewire-portal" || bad "unexpected camera stack"
[ "$CAMERA_BACKEND" = "libcamera" ] &&
  ok "backend is libcamera" || bad "unexpected camera backend"
[ "$CAMERA_TRANSPORT" = "PipeWire" ] &&
  ok "transport is PipeWire" || bad "unexpected camera transport"
[ "$CAMERA_PORTAL" = "xdg-desktop-portal" ] &&
  ok "portal is the permission boundary" || bad "unexpected camera portal"
[ "$CAMERA_PERMISSION_MODE" = "portal" ] &&
  ok "permission mode is the portal" || bad "permission mode is not the portal"
[ "$CAMERA_DIRECT_V4L2" = "false" ] &&
  ok "direct V4L2 is disabled" || bad "direct V4L2 is enabled"
[ "$CAMERA_STORE_CAPTURES" = "false" ] &&
  ok "captures are not stored by the image" || bad "capture storage is enabled"
[ "$CAMERA_UPLOAD_CAPTURES" = "false" ] &&
  ok "captures are not uploaded" || bad "capture upload is enabled"
[ "$CAMERA_LOG_IMAGE_DATA" = "false" ] &&
  ok "image data is not logged" || bad "image-data logging is enabled"
[ "$CAMERA_LOG_CAPTURE_PATHS" = "false" ] &&
  ok "capture paths are not logged" || bad "capture-path logging is enabled"
[ "$CAMERA_BUNDLE_TEST_IMAGES" = "false" ] &&
  ok "test images are not bundled" || bad "test images are bundled"
[ "$CAMERA_TEST_PATTERN" = "generated" ] &&
  ok "fallback is a generated test pattern" || bad "fallback is not generated"
for package in libcamera libcamera-tools pipewire pipewire-spa-libcamera xdg-desktop-portal xdg-desktop-portal-gnome; do
  case " $CAMERA_PACKAGES " in
    *" $package "*) ok "camera package: $package" ;;
    *) bad "camera package missing: $package" ;;
  esac
done
case "$CAMERA_BRIDGE" in
  scripts/*) ok "bridge lives in the checkout" ;;
  *) bad "bridge path is not repository-relative" ;;
esac

for file in \
  config/camera/camera.conf \
  scripts/camera-bridge.py \
  tests/camera/fake_camera_portal.py \
  tests/camera/test_camera_bridge.py \
  tests/camera/test_shell_camera.py \
  docs/adr/0004-camera-and-media-capture.md \
  docs/camera.md \
  docs/qemu-camera-checklist.md \
  docs/camera-supported-devices.md \
  shell/components/CameraService.qml \
  shell/components/CameraTestPattern.qml \
  shell/surfaces/CameraSurface.qml; do
  check_file "$file"
done

for file in scripts/camera-bridge.py tests/camera/fake_camera_portal.py tests/camera/test_camera_bridge.py tests/camera/test_shell_camera.py; do
  if [ -x "$file" ]; then ok "$file executable"; else bad "$file not executable"; fi
  if python3 -m py_compile "$file"; then ok "$file compiles"; else bad "$file does not compile"; fi
done

log "== build integration =="
check_text config/build.conf 'CAMERA_CONFIG="$ROOT/config/camera/camera.conf"' "build config sources camera policy"
check_text scripts/build.sh 'extra_packages = $KEYBOARD_PACKAGE $POWER_PACKAGES $MODEM_PACKAGES $CAMERA_PACKAGES' "image installs camera packages"
check_text scripts/build.sh 'would install camera packages' "build dry run reports camera packages"
check_text scripts/lib.sh "CAMERA_CONFIG" "config gate requires camera config"
check_text scripts/lib.sh "CAMERA_PACKAGES" "config gate validates camera packages"
check_text scripts/lib.sh "CAMERA_DIRECT_V4L2" "config gate rejects direct V4L2"
check_text scripts/lib.sh "CAMERA_BUNDLE_TEST_IMAGES" "config gate rejects bundled images"
check_text Makefile "camera-test:" "Makefile exposes camera-test"
check_text tests/all.sh "tests/camera.sh" "full test gate runs camera checks"

log "== generated patterns, not photos =="
if git ls-files -- 'docs/camera*' 'tests/camera/*' 'shell/*camera*' |
  grep -qiE '\.(png|jpe?g|webp|heic|avif|gif|bmp|tiff?)$'; then
  bad "a photo or test image is tracked in the camera tree"
else
  ok "no photo or test image is tracked in the camera tree"
fi
if git ls-files | grep -qiE '\.(png|jpe?g|webp|heic|avif|gif|bmp|tiff?)$'; then
  bad "the repository tracks a raster image; use a generated pattern instead"
else
  ok "the repository tracks no raster images"
fi
if grep -RInE --binary-files=without-match -e 'data:image/' \
  scripts/camera-bridge.py shell/components/CameraService.qml \
  shell/components/CameraTestPattern.qml shell/surfaces/CameraSurface.qml \
  >/dev/null 2>&1; then
  bad "camera code embeds an image payload"
else
  ok "camera code embeds no image payload"
fi

log "== no privileged commands or personal-data logging =="
if grep -RInE --binary-files=without-match --exclude='camera.sh' \
  -e '(^|[^[:alnum:]_])(sudo|pkexec|systemctl|pacman|mount)([[:space:]]|$)' \
  scripts/camera-bridge.py tests/camera/fake_camera_portal.py \
  tests/camera/test_camera_bridge.py tests/camera/test_shell_camera.py \
  >/dev/null 2>&1; then
  bad "camera code invokes a privileged command"
else
  ok "camera code invokes no privileged command"
fi

if grep -nE --binary-files=without-match \
  -e '(^|[^[:alnum:]_])print\(' \
  -e 'traceback\.print' \
  -e 'sys\.stderr\.write\([^)]*(image|frame|photo|path)' \
  scripts/camera-bridge.py >/dev/null 2>&1; then
  bad "camera bridge can print image data or a traceback"
else
  ok "camera bridge does not print image data or a traceback"
fi

if grep -RInE --binary-files=without-match 'console\.(log|debug|warn|error)\(' \
  shell/components/CameraService.qml \
  shell/components/CameraTestPattern.qml \
  shell/surfaces/CameraSurface.qml \
  >/dev/null 2>&1; then
  bad "camera QML writes to the console"
else
  ok "camera QML writes nothing to the console"
fi

log "== bridge CLI =="
if scripts/camera-bridge.py --help >"$tmp/bridge-help.log" 2>&1 &&
  grep -qF -- "--request" "$tmp/bridge-help.log" &&
  grep -qF -- "--test-pattern" "$tmp/bridge-help.log" &&
  grep -qF -- "--capture" "$tmp/bridge-help.log"; then
  ok "bridge help documents state, permission, capture and the test pattern"
else
  bad "bridge help is unavailable or incomplete"
fi

log "== generated test pattern =="
if scripts/camera-bridge.py --test-pattern "$tmp/pattern.png" \
  --width 320 --height 240 >"$tmp/pattern.json" 2>"$tmp/pattern.err"; then
  if python3 - "$tmp/pattern.png" "$tmp/pattern.json" <<'PY'
import json
import struct
import sys

with open(sys.argv[1], "rb") as handle:
    data = handle.read()
with open(sys.argv[2], encoding="utf-8") as handle:
    payload = json.load(handle)

assert data[:8] == b"\x89PNG\r\n\x1a\n"
assert struct.unpack(">II", data[16:24]) == (320, 240)
assert payload["type"] == "test-pattern"
assert payload["generated"] is True
assert b"not a photograph" in data
assert len(data) < 1024 * 1024
PY
  then
    ok "test pattern is a generated 320x240 PNG"
  else
    bad "generated test pattern is not valid"
  fi
else
  cat "$tmp/pattern.err" >&2
  bad "test pattern generation failed"
fi

log "== emulated Camera portal and capture pipeline =="
if command -v dbus-run-session >/dev/null 2>&1 &&
  python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' >/dev/null 2>&1; then
  if timeout 120s dbus-run-session -- python3 "$ROOT/tests/camera/test_camera_bridge.py" \
    >"$tmp/bridge-test.log" 2>&1; then
    cat "$tmp/bridge-test.log"
    ok "emulated portal permission, no-camera, fallback and capture pipeline"
  else
    cat "$tmp/bridge-test.log" >&2
    bad "emulated portal permission, no-camera, fallback and capture pipeline"
  fi
else
  log "skip emulated Camera portal flow (dbus-run-session or Gio missing)"
fi

log "== shell camera process =="
if command -v dbus-run-session >/dev/null 2>&1 &&
  command -v quickshell >/dev/null 2>&1 &&
  python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' >/dev/null 2>&1; then
  if timeout 120s dbus-run-session -- python3 "$ROOT/tests/camera/test_shell_camera.py" \
    >"$tmp/shell-camera.log" 2>&1; then
    cat "$tmp/shell-camera.log"
    ok "shell starts the bridge, reads the portal camera and requests access"
  else
    cat "$tmp/shell-camera.log" >&2
    bad "shell camera process check"
  fi
else
  log "skip shell camera process check (dbus-run-session, quickshell or Gio missing)"
fi

if [ "$fail" -eq 0 ]; then
  log "all camera checks passed"
fi
[ "$fail" -eq 0 ]
