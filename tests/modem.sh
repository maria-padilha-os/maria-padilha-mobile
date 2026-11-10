#!/usr/bin/env bash
# Cellular modem, calls and SMS checks.
#
# The static checks are unprivileged. The integration checks either use the
# emulated ModemManager D-Bus service in tests/modem/ or start a real
# ModemManager daemon on a private session bus with no modem. They never place
# a real call, send a real SMS, or touch a physical modem.

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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/padilha-modem-test.XXXXXX")
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

log "== modem decision and docs =="
adr=docs/adr/0003-modem-and-telephony.md
if [ -s "$adr" ]; then
  ok "$adr"
  check_text "$adr" "## Decision" "ADR has a decision"
  check_text "$adr" "## Options considered" "ADR compares options"
  check_text "$adr" "ModemManager" "ADR documents ModemManager"
  check_text "$adr" "oFono" "ADR compares oFono"
  check_text "$adr" "org.freedesktop.ModemManager1.Modem.Voice" "ADR names the Voice interface"
  check_text "$adr" "org.freedesktop.ModemManager1.Modem.Messaging" "ADR names the Messaging interface"
  check_text "$adr" "## Consequences" "ADR records consequences"
  check_text "$adr" "## Privacy contract" "ADR records the privacy contract"
  check_text "$adr" "No real call" "ADR refuses a real call/SMS claim"
  check_text "$adr" "## Sources" "ADR has sources"
else
  bad "$adr missing"
fi

for doc in docs/modem.md docs/qemu-telephony-checklist.md; do
  check_file "$doc"
done
check_text docs/modem.md "## Components" "modem docs list components"
check_text docs/modem.md "## No-modem and modem-unavailable states" "modem docs cover graceful states"
check_text docs/modem.md "## Calls" "modem docs cover calls"
check_text docs/modem.md "## SMS" "modem docs cover SMS"
check_text docs/modem.md "## Privacy contract" "modem docs cover privacy"
check_text docs/modem.md "## Known limitations" "modem docs state limitations"
check_text docs/qemu-telephony-checklist.md "# Manual QEMU telephony checklist" "checklist title"
check_text docs/qemu-telephony-checklist.md "No real call/SMS claim" "checklist refuses a hardware claim"
check_text docs/qemu-telephony-checklist.md "emulated" "checklist uses the emulated service"

for needle in \
  "docs/adr/0003-modem-and-telephony.md" \
  "docs/modem.md" \
  "docs/qemu-telephony-checklist.md" \
  "make modem-test" \
  "MM Voice" \
  "MM Messaging"; do
  check_text README.md "$needle" "README modem link/text: $needle"
done

log "== modem config =="
# shellcheck source=../config/modem/modem.conf
. "$ROOT/config/modem/modem.conf"
[ "$MODEM_BACKEND" = "ModemManager" ] &&
  ok "backend is ModemManager" || bad "backend is not ModemManager"
[ "$MODEM_PACKAGE" = "modemmanager" ] &&
  ok "package is modemmanager" || bad "package is not modemmanager"
[ "$MODEM_CALLS_ENABLED" = "true" ] &&
  ok "calls are enabled" || bad "calls are disabled"
[ "$MODEM_SMS_ENABLED" = "true" ] &&
  ok "SMS is enabled" || bad "SMS is disabled"
[ "$MODEM_STORE_MESSAGES" = "false" ] &&
  ok "shell does not store message contents" || bad "message storage is enabled"
[ "$MODEM_STORE_CREDENTIALS" = "false" ] &&
  ok "shell does not store credentials" || bad "credential storage is enabled"
[ "$MODEM_LOG_MESSAGE_CONTENT" = "false" ] &&
  ok "message content is not logged" || bad "message content logging is enabled"
[ "$MODEM_LOG_CREDENTIALS" = "false" ] &&
  ok "credentials are not logged" || bad "credential logging is enabled"
[ "$MODEM_LOG_PHONE_NUMBERS" = "false" ] &&
  ok "phone numbers are not logged" || bad "phone-number logging is enabled"
[ "$MODEM_EMERGENCY_CALLS" = "false" ] &&
  ok "emergency calls are not claimed" || bad "emergency calls are claimed"
case "$MODEM_BRIDGE" in
  scripts/*) ok "bridge lives in the checkout" ;;
  *) bad "bridge path is not repository-relative" ;;
esac

for file in \
  config/modem/modem.conf \
  scripts/telephony-bridge.py \
  tests/modem/fake_modemmanager.py \
  tests/modem/test_telephony_bridge.py \
  tests/modem/test_shell_telephony.py \
  docs/adr/0003-modem-and-telephony.md \
  docs/modem.md \
  docs/qemu-telephony-checklist.md; do
  check_file "$file"
done

for file in scripts/telephony-bridge.py tests/modem/fake_modemmanager.py tests/modem/test_telephony_bridge.py tests/modem/test_shell_telephony.py; do
  if [ -x "$file" ]; then ok "$file executable"; else bad "$file not executable"; fi
  if python3 -m py_compile "$file"; then ok "$file compiles"; else bad "$file does not compile"; fi
done

log "== build integration =="
check_text config/build.conf 'MODEM_CONFIG="$ROOT/config/modem/modem.conf"' "build config sources modem policy"
check_text scripts/build.sh 'extra_packages = $KEYBOARD_PACKAGE $POWER_PACKAGES $MODEM_PACKAGES' "image installs modem packages"
check_text scripts/build.sh 'would install modem packages' "build dry run reports modem packages"
check_text scripts/lib.sh "MODEM_CONFIG" "config gate requires modem config"
check_text scripts/lib.sh "MODEM_PACKAGES" "config gate validates modem packages"
check_text Makefile "modem-test:" "Makefile exposes modem-test"

log "== no privileged commands or personal-info logging =="
if grep -RInE --binary-files=without-match \
  -e '(^|[^[:alnum:]_])(sudo|pkexec|systemctl|pacman|mount)([[:space:]]|$)' \
  scripts/telephony-bridge.py tests/modem/fake_modemmanager.py tests/modem/test_telephony_bridge.py tests/modem/test_shell_telephony.py \
  >/dev/null 2>&1; then
  bad "telephony code invokes a privileged command"
else
  ok "telephony code invokes no privileged command"
fi

if grep -RInE --binary-files=without-match --exclude='modem.sh' -- '--log-personal-info' \
  config scripts tests shell >/dev/null 2>&1; then
  bad "ModemManager personal-info logging is present"
else
  ok "ModemManager personal-info logging is absent"
fi

if grep -nE --binary-files=without-match \
  -e '(^|[^[:alnum:]_])print\(' \
  -e 'traceback\.print' \
  -e 'sys\.stderr\.write\([^)]*(text|number|pin|puk|message)' \
  scripts/telephony-bridge.py >/dev/null 2>&1; then
  bad "telephony bridge can print content or a traceback"
else
  ok "telephony bridge does not print content or a traceback"
fi

if grep -RInE --binary-files=without-match 'console\.(log|debug|warn|error)\(' \
  shell/components/TelephonyService.qml \
  shell/components/TelephonyStatusCard.qml \
  shell/components/CallCard.qml \
  shell/components/SmsCard.qml \
  shell/components/DialPad.qml \
  shell/surfaces/CallsSurface.qml \
  shell/surfaces/MessagesSurface.qml \
  >/dev/null 2>&1; then
  bad "telephony QML writes to the console"
else
  ok "telephony QML writes nothing to the console"
fi

log "== bridge CLI =="
if scripts/telephony-bridge.py --help >"$tmp/bridge-help.log" 2>&1 &&
  grep -qF -- "--session-bus" "$tmp/bridge-help.log"; then
  ok "bridge help documents the test bus"
else
  bad "bridge help is unavailable"
fi

run_real_no_modem_check() {
  local out=$1 script=$2
  cat >"$script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=$1
ModemManager --test-session --test-no-udev --no-auto-scan --log-level=ERR >/dev/null 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
  if mmcli --test-session -B >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
"$ROOT/scripts/telephony-bridge.py" --session-bus --once >"$out"
EOF
  chmod +x "$script"
  ROOT="$ROOT" timeout 25s dbus-run-session -- "$script" "$out"
}

if command -v dbus-run-session >/dev/null 2>&1 &&
  command -v ModemManager >/dev/null 2>&1 &&
  command -v mmcli >/dev/null 2>&1 &&
  python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' >/dev/null 2>&1; then
  log "== real ModemManager, no modem =="
  if run_real_no_modem_check "$tmp/no-modem.json" "$tmp/real-mm.sh" >"$tmp/real-mm.log" 2>&1; then
    if python3 - "$tmp/no-modem.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

assert data["type"] == "snapshot"
assert data["backend"] == "ModemManager"
assert data["available"] is True
assert data["state"] == "no-modem"
assert data["modems"] == []
assert data["calls"] == []
assert data["messages"] == []
PY
    then
      ok "real ModemManager session with no modem is a graceful no-modem state"
    else
      bad "real ModemManager no-modem snapshot is wrong"
    fi
  else
    cat "$tmp/real-mm.log" >&2
    bad "real ModemManager session check failed"
  fi
else
  log "skip real ModemManager session check (dbus-run-session, ModemManager, mmcli or Gio missing)"
fi

log "== emulated ModemManager calls and SMS =="
if command -v dbus-run-session >/dev/null 2>&1 &&
  python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' >/dev/null 2>&1; then
  if timeout 120s dbus-run-session -- python3 "$ROOT/tests/modem/test_telephony_bridge.py" \
    >"$tmp/bridge-test.log" 2>&1; then
    cat "$tmp/bridge-test.log"
    ok "emulated ModemManager call/SMS/state flow"
  else
    cat "$tmp/bridge-test.log" >&2
    bad "emulated ModemManager call/SMS/state flow"
  fi
else
  log "skip emulated ModemManager flow (dbus-run-session or Gio missing)"
fi

log "== shell telephony process =="
if command -v dbus-run-session >/dev/null 2>&1 &&
  command -v quickshell >/dev/null 2>&1 &&
  python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' >/dev/null 2>&1; then
  if timeout 120s dbus-run-session -- python3 "$ROOT/tests/modem/test_shell_telephony.py" \
    >"$tmp/shell-telephony.log" 2>&1; then
    cat "$tmp/shell-telephony.log"
    ok "shell starts the bridge and reads a live ModemManager snapshot"
  else
    cat "$tmp/shell-telephony.log" >&2
    bad "shell telephony process check"
  fi
else
  log "skip shell telephony process check (dbus-run-session, quickshell or Gio missing)"
fi

if [ "$fail" -eq 0 ]; then
  log "all modem checks passed"
fi
[ "$fail" -eq 0 ]
