#!/usr/bin/env bash
# Power, battery, thermal, suspend and staging checks.
#
# These checks are unprivileged. They use a fake sysfs tree for battery and
# threshold paths, never apply a threshold, never suspend, and never invoke
# sudo, pkexec, systemctl, pacman or mount.

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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/padilha-power-test.XXXXXX")
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

make_qemu_fixture() {
  local base=$1
  mkdir -p \
    "$base/class/power_supply/BAT0" \
    "$base/class/power_supply/AC" \
    "$base/class/thermal/thermal_zone0" \
    "$base/class/thermal/thermal_zone1" \
    "$base/firmware/devicetree/base" \
    "$base/power" \
    "$base/class/wakeup/wakeup0/power"

  printf '%s\n' Battery >"$base/class/power_supply/BAT0/type"
  printf '%s\n' Charging >"$base/class/power_supply/BAT0/status"
  printf '%s\n' 1 >"$base/class/power_supply/BAT0/present"
  printf '%s\n' 82 >"$base/class/power_supply/BAT0/capacity"
  printf '%s\n' Good >"$base/class/power_supply/BAT0/health"
  printf '%s\n' Li-ion >"$base/class/power_supply/BAT0/technology"
  printf '%s\n' "Padilha test battery" >"$base/class/power_supply/BAT0/model_name"
  printf '%s\n' 4200000 >"$base/class/power_supply/BAT0/voltage_now"
  printf '%s\n' 500000 >"$base/class/power_supply/BAT0/current_now"
  printf '%s\n' 2100000 >"$base/class/power_supply/BAT0/power_now"
  printf '%s\n' 300 >"$base/class/power_supply/BAT0/temp"
  printf '%s\n' 42 >"$base/class/power_supply/BAT0/cycle_count"
  printf '%s\n' 20 >"$base/class/power_supply/BAT0/charge_control_start_threshold"
  printf '%s\n' 80 >"$base/class/power_supply/BAT0/charge_control_end_threshold"

  printf '%s\n' Mains >"$base/class/power_supply/AC/type"
  printf '%s\n' 1 >"$base/class/power_supply/AC/online"

  printf '%s\n' cpu-thermal >"$base/class/thermal/thermal_zone0/type"
  printf '%s\n' 48000 >"$base/class/thermal/thermal_zone0/temp"
  printf '%s\n' battery >"$base/class/thermal/thermal_zone1/type"
  printf '%s\n' 31000 >"$base/class/thermal/thermal_zone1/temp"

  printf '%s\n' "QEMU aarch64" >"$base/firmware/devicetree/base/model"
  printf '%s\n' "qemu,arm-virt" >"$base/firmware/devicetree/base/compatible"
  printf '%s\n' "freeze mem" >"$base/power/state"
  printf '%s\n' "[s2idle] shallow deep" >"$base/power/mem_sleep"
  printf '%s\n' "gpio-keys" >"$base/class/wakeup/wakeup0/name"
  printf '%s\n' enabled >"$base/class/wakeup/wakeup0/power/wakeup"
}

make_laptop_fixture() {
  local base=$1
  mkdir -p "$base/class/dmi/id" "$base/power"
  printf '%s\n' "ThinkPad T14 test fixture" >"$base/class/dmi/id/product_name"
  printf '%s\n' 10 >"$base/class/dmi/id/chassis_type"
  printf '%s\n' "freeze mem disk" >"$base/power/state"
  printf '%s\n' "[s2idle]" >"$base/power/mem_sleep"
}

qemu_sysfs="$tmp/qemu-sysfs"
unsupported_sysfs="$tmp/unsupported-sysfs"
laptop_sysfs="$tmp/laptop-sysfs"
make_qemu_fixture "$qemu_sysfs"
cp -a "$qemu_sysfs" "$unsupported_sysfs"
rm -f \
  "$unsupported_sysfs/class/power_supply/BAT0/charge_control_start_threshold" \
  "$unsupported_sysfs/class/power_supply/BAT0/charge_control_end_threshold"
printf '%s\n' "auto" >"$unsupported_sysfs/class/power_supply/BAT0/charge_behaviour"
make_laptop_fixture "$laptop_sysfs"

log "== power config and files =="
# shellcheck source=../config/power/power.conf
. "$ROOT/config/power/power.conf"
[ "$POWER_CHARGE_THRESHOLD_MODE" = "apply-if-supported" ] &&
  ok "threshold mode is hardware-gated" || bad "threshold mode is not hardware-gated"
[ "$POWER_CHARGE_THRESHOLD_START" -lt "$POWER_CHARGE_THRESHOLD_END" ] &&
  ok "charge window is start < end" || bad "charge window is invalid"
[ "$POWER_SUSPEND_ALLOW_HIBERNATE" = "false" ] &&
  ok "hibernation is disabled" || bad "hibernation is enabled"
[ "$POWER_SUSPEND_ALLOW_HYBRID_SLEEP" = "false" ] &&
  ok "hybrid sleep is disabled" || bad "hybrid sleep is enabled"
[ "$POWER_SUSPEND_ALLOW_SUSPEND_THEN_HIBERNATE" = "false" ] &&
  ok "suspend-then-hibernate is disabled" || bad "suspend-then-hibernate is enabled"
[ "$POWER_IDLE_ACTION" = "ignore" ] &&
  ok "logind idle is left to Phosh" || bad "logind idle action conflicts with Phosh"
[ "$POWER_DIAGNOSTIC_READ_ONLY" = "true" ] &&
  ok "diagnostic is read-only" || bad "diagnostic read-only contract is not set"

for file in \
  config/power/power.conf \
  config/power/systemd/maria-padilha-charge-thresholds.service \
  config/power/systemd/sleep.conf.d/10-maria-padilha-sleep.conf \
  config/power/systemd/logind.conf.d/10-maria-padilha-power.conf \
  config/power/udev/90-maria-padilha-charge-thresholds.rules \
  docs/power.md \
  docs/qemu-power-checklist.md \
  scripts/power-charge-thresholds.sh \
  scripts/power-diagnostic.sh \
  scripts/power-sleep-hook.sh \
  scripts/power-suspend-check.sh \
  scripts/stage-power-config.sh; do
  check_file "$file"
done

for file in \
  scripts/power-charge-thresholds.sh \
  scripts/power-diagnostic.sh \
  scripts/power-sleep-hook.sh \
  scripts/power-suspend-check.sh \
  scripts/stage-power-config.sh; do
  if [ -x "$file" ]; then ok "$file executable"; else bad "$file not executable"; fi
  if bash -n "$file"; then ok "$file syntax"; else bad "$file syntax"; fi
done

check_text config/build.conf 'POWER_CONFIG="$ROOT/config/power/power.conf"' "build config sources power policy"
check_text scripts/build.sh 'extra_packages = $KEYBOARD_PACKAGE $POWER_PACKAGES' "image installs power packages"
check_text scripts/build.sh 'would install power packages' "build dry run reports power packages"
check_text README.md 'docs/power.md' "README links the power documentation"
check_text README.md 'make power-test' "README documents the power test"
check_text docs/power.md "## Known limitations" "power docs have known limitations"
check_text docs/power.md "## Charge thresholds" "power docs cover charge thresholds"
check_text docs/power.md "## Thermal readings" "power docs cover thermal readings"
check_text docs/power.md "## Suspend and resume policy" "power docs cover suspend/resume"
check_text docs/power.md "## No always-on background loops" "power docs cover idle loops"
check_text docs/power.md "scripts/power-diagnostic.sh" "power docs document the diagnostic"
check_text docs/qemu-power-checklist.md "Do not run the suspend step on" "checklist forbids laptop suspend"
check_text docs/qemu-power-checklist.md "No physical-device claim" "checklist refuses physical claims"

log "== no privileged commands or always-on loops =="
power_scripts=(
  scripts/power-charge-thresholds.sh
  scripts/power-diagnostic.sh
  scripts/power-sleep-hook.sh
  scripts/power-suspend-check.sh
  scripts/stage-power-config.sh
)
if awk '
  /^[[:space:]]*#/ { next }
  {
    line = $0
    sub(/#.*/, "", line)
    if (line ~ /(^|[;&|[:space:]])(sudo|pkexec|systemctl|pacman|mount)([[:space:]]|$)/) {
      print FILENAME ":" FNR ":" $0
      bad = 1
    }
  }
  END { exit bad }
' "${power_scripts[@]}"; then
  ok "power scripts invoke no privileged command"
else
  bad "power script invokes a privileged command"
fi

if grep -nE '(^|[[:space:]])while[[:space:]]+(true|:)|for[[:space:]]*\(\([[:space:]]*;;' \
  "${power_scripts[@]}" >/dev/null 2>&1; then
  bad "power script contains an always-on loop"
else
  ok "power scripts contain no always-on loop"
fi

if find config/power -type f \( -name '*.timer' -o -name '*.service' \) -print | grep -q .; then
  if grep -RInE '^[[:space:]]*(Restart|RuntimeMaxSec|WatchdogSec)=' config/power >/dev/null 2>&1; then
    bad "power service has a restart or watchdog loop"
  else
    ok "power service is one-shot with no restart loop"
  fi
fi
if find config/power -type f -name '*.timer' -print | grep -q .; then
  bad "power config contains a timer unit"
else
  ok "power config contains no timer unit"
fi

log "== diagnostic JSON =="
diag_json=$("$ROOT/scripts/power-diagnostic.sh" --sysfs "$qemu_sysfs" --json)
printf '%s\n' "$diag_json" >"$tmp/diagnostic.json"
if python3 - "$tmp/diagnostic.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

assert data["schema"] == 1
assert data["read_only"] is True
assert data["platform"]["kind"] == "qemu"
assert data["battery"]["count"] == 1
assert data["battery"]["external_power"] is True
battery = data["battery"]["devices"][0]
assert battery["name"] == "BAT0"
assert battery["present"] is True
assert battery["status"] == "Charging"
assert battery["capacity_percent"] == 82
assert battery["temperature_c"] == 30.0
assert battery["charge_thresholds"]["supported"] is True
assert battery["charge_thresholds"]["start"] == 20
assert battery["charge_thresholds"]["end"] == 80
zones = {zone["zone"]: zone for zone in data["thermal"]["zones"]}
assert zones["cpu-thermal"]["temperature_c"] == 48.0
assert zones["battery"]["temperature_c"] == 31.0
assert data["thermal"]["warn_c"] == 65
assert data["thermal"]["critical_c"] == 80
assert data["suspend"]["supported"] is True
assert data["suspend"]["hibernate_allowed"] is False
assert data["suspend"]["hybrid_sleep_allowed"] is False
assert data["suspend"]["idle_action"] == "ignore"
assert data["warnings"] == []
PY
then
  ok "diagnostic JSON fixture assertions"
else
  bad "diagnostic JSON fixture assertions"
fi

diag_text=$("$ROOT/scripts/power-diagnostic.sh" --sysfs "$qemu_sysfs")
for needle in \
  "battery BAT0: present=1 status=Charging capacity=82%" \
  "charge_thresholds: supported=true start=20 end=80" \
  "cpu-thermal: 48.0 C" \
  "supported: true" \
  "read-only: true"; do
  if printf '%s\n' "$diag_text" | grep -qF -- "$needle"; then
    ok "diagnostic text: $needle"
  else
    bad "diagnostic text missing: $needle"
  fi
done

log "== unsupported hardware is a no-op =="
unsupported_json=$("$ROOT/scripts/power-diagnostic.sh" --sysfs "$unsupported_sysfs" --json)
if printf '%s\n' "$unsupported_json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
battery = data["battery"]["devices"][0]
assert battery["charge_thresholds"]["supported"] is False
assert battery["charge_thresholds"]["start"] is None
assert battery["charge_thresholds"]["end"] is None
'; then
  ok "diagnostic reports unsupported thresholds"
else
  bad "diagnostic did not report unsupported thresholds"
fi

unsupported_plan=$("$ROOT/scripts/power-charge-thresholds.sh" --sysfs "$unsupported_sysfs" --dry-run)
if printf '%s\n' "$unsupported_plan" | grep -qF "no standard charge threshold attribute" &&
  printf '%s\n' "$unsupported_plan" | grep -qF "no-op"; then
  ok "unsupported threshold helper is a no-op"
else
  bad "unsupported threshold helper is not a no-op"
fi

log "== threshold dry run never writes =="
threshold_manifest() {
  find "$1/class/power_supply" -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
}
before=$(threshold_manifest "$qemu_sysfs")
plan=$("$ROOT/scripts/power-charge-thresholds.sh" --sysfs "$qemu_sysfs" --dry-run)
after=$(threshold_manifest "$qemu_sysfs")
if printf '%s\n' "$plan" | grep -qF "would set class/power_supply/BAT0/charge_control_start_threshold = 20" &&
  printf '%s\n' "$plan" | grep -qF "would set class/power_supply/BAT0/charge_control_end_threshold = 80" &&
  printf '%s\n' "$plan" | grep -qF "dry run complete; no threshold was written"; then
  ok "threshold dry run prints the plan"
else
  bad "threshold dry run plan is incomplete"
fi
if [ "$before" = "$after" ]; then
  ok "threshold dry run changed no files"
else
  bad "threshold dry run changed sysfs files"
fi

if [ "$(id -u)" -ne 0 ]; then
  set +e
  apply_out=$("$ROOT/scripts/power-charge-thresholds.sh" --sysfs "$qemu_sysfs" --apply 2>&1)
  apply_rc=$?
  set -e
  if [ "$apply_rc" -ne 0 ] && printf '%s\n' "$apply_out" | grep -qF "requires root"; then
    ok "apply refuses to write without root"
  else
    bad "apply did not refuse a non-root write"
  fi
  after_apply=$(threshold_manifest "$qemu_sysfs")
  if [ "$before" = "$after_apply" ]; then
    ok "refused apply changed no files"
  else
    bad "refused apply changed sysfs files"
  fi
else
  log "skip non-root apply refusal (tests are running as root)"
fi

log "== suspend target guard =="
set +e
qemu_guard=$("$ROOT/scripts/power-suspend-check.sh" --sysfs "$qemu_sysfs" 2>&1)
qemu_guard_rc=$?
laptop_guard=$("$ROOT/scripts/power-suspend-check.sh" --sysfs "$laptop_sysfs" 2>&1)
laptop_guard_rc=$?
set -e
if [ "$qemu_guard_rc" -eq 0 ] && printf '%s\n' "$qemu_guard" | grep -qF "ALLOW"; then
  ok "QEMU target is allowed to run the manual suspend checklist"
else
  bad "QEMU target was refused (rc=$qemu_guard_rc)"
fi
if [ "$laptop_guard_rc" -ne 0 ] &&
  printf '%s\n' "$laptop_guard" | grep -qF "REFUSE" &&
  printf '%s\n' "$laptop_guard" | grep -qF "laptop"; then
  ok "laptop target refuses the suspend test"
else
  bad "laptop target did not refuse the suspend test"
fi
if printf '%s\n' "$qemu_guard" | grep -qF "did not suspend anything"; then
  ok "target guard does not suspend"
else
  bad "target guard did not state that it is read-only"
fi

log "== sleep hook =="
if "$ROOT/scripts/power-sleep-hook.sh" pre; then ok "sleep hook pre is a no-op"; else bad "sleep hook pre failed"; fi
set +e
"$ROOT/scripts/power-sleep-hook.sh" post >"$tmp/sleep-post.log" 2>&1
sleep_post_rc=$?
"$ROOT/scripts/power-sleep-hook.sh" invalid >"$tmp/sleep-invalid.log" 2>&1
sleep_invalid_rc=$?
set -e
if [ "$sleep_post_rc" -eq 0 ]; then ok "sleep hook post does not fail resume"; else bad "sleep hook post fails resume"; fi
if [ "$sleep_invalid_rc" -ne 0 ]; then ok "sleep hook rejects unknown phase"; else bad "sleep hook accepts unknown phase"; fi

log "== staging tree =="
stage="$tmp/stage-root"
if "$ROOT/scripts/stage-power-config.sh" --dest "$stage" >"$tmp/stage.log" 2>&1; then
  ok "power configuration stages without root"
else
  cat "$tmp/stage.log" >&2
  bad "power configuration staging failed"
fi
for relative in \
  etc/maria-padilha/power.conf \
  usr/libexec/maria-padilha/power-charge-thresholds \
  usr/lib/systemd/system-sleep/maria-padilha-power \
  etc/systemd/system/maria-padilha-charge-thresholds.service \
  etc/systemd/sleep.conf.d/10-maria-padilha-sleep.conf \
  etc/systemd/logind.conf.d/10-maria-padilha-power.conf \
  etc/udev/rules.d/90-maria-padilha-charge-thresholds.rules \
  usr/share/doc/maria-padilha-mobile/power.md; do
  check_file "$stage/$relative"
done
if [ -L "$stage/etc/systemd/system/multi-user.target.wants/maria-padilha-charge-thresholds.service" ]; then
  ok "charge-threshold oneshot is enabled in the staging tree"
else
  bad "charge-threshold oneshot is not enabled in the staging tree"
fi
check_text "$stage/etc/systemd/system/maria-padilha-charge-thresholds.service" "Type=oneshot" "staged service is oneshot"
if grep -qE '^[[:space:]]*(Restart|RuntimeMaxSec|WatchdogSec)=' \
  "$stage/etc/systemd/system/maria-padilha-charge-thresholds.service"; then
  bad "staged service has a restart/watchdog loop"
else
  ok "staged service has no restart/watchdog loop"
fi

dry_stage="$tmp/dry-stage-root"
if "$ROOT/scripts/stage-power-config.sh" --dest "$dry_stage" --dry-run >"$tmp/stage-dry.log" 2>&1 &&
  [ ! -e "$dry_stage" ] &&
  grep -qF "dry run complete" "$tmp/stage-dry.log"; then
  ok "staging dry run writes nothing"
else
  bad "staging dry run wrote files or failed"
fi

if [ "$fail" -eq 0 ]; then
  log "all power checks passed"
fi
[ "$fail" -eq 0 ]
