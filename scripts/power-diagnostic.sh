#!/usr/bin/env bash
# Read-only power, battery, thermal and suspend diagnostic for Maria Padilha.
#
# The script performs exactly one scan and exits. It never writes sysfs, never
# starts a daemon/timer and never invokes sudo, pkexec, systemctl, pacman or
# mount. Run it in the checkout, in the QEMU guest, or on a supported phone.
#
# The --sysfs override exists so tests can point at a fixture tree. It is also
# useful for inspecting a mounted image without booting it.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/power/power.conf
. "$ROOT/config/power/power.conf"

SYSFS="/sys"
FORMAT="text"
STRICT=false
CONFIG_FILE="$ROOT/config/power/power.conf"

die() {
  printf 'FAIL %s\n' "$*" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage: scripts/power-diagnostic.sh [options]

Options:
  --sysfs DIR    read power/thermal data from DIR instead of /sys
  --config FILE  read policy from FILE instead of config/power/power.conf
  --json         emit machine-readable JSON
  --strict       exit 1 when the scan reports any warning
  -h, --help     show this help

The scan is read-only and one-shot. It does not suspend, change thresholds or
run any privileged command.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sysfs)
      [ "$#" -ge 2 ] || die "--sysfs needs a directory"
      SYSFS="$2"
      shift
      ;;
    --config)
      [ "$#" -ge 2 ] || die "--config needs a file"
      CONFIG_FILE="$2"
      shift
      ;;
    --json) FORMAT="json" ;;
    --strict) STRICT=true ;;
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

[ -d "$SYSFS" ] || die "sysfs path does not exist: $SYSFS"
[ -f "$CONFIG_FILE" ] || die "power policy file does not exist: $CONFIG_FILE"
if [ "$CONFIG_FILE" != "$ROOT/config/power/power.conf" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

# Read a small sysfs attribute without failing when the kernel does not expose
# it. Values are trimmed of the trailing newline and any NUL padding in
# devicetree strings.
read_value() {
  local file="$1"
  [ -r "$file" ] || {
    printf ''
    return 0
  }
  tr -d '\r\n\000' <"$file" 2>/dev/null || true
}

is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

json_escape() {
  local value="${1:-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

json_string() {
  printf '"%s"' "$(json_escape "${1:-}")"
}

json_number() {
  local value="${1:-}"
  if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "$value"
  else
    printf 'null'
  fi
}

json_bool() {
  if [ "${1:-false}" = "true" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

# Platform detection never calls systemd-detect-virt or any other helper. It
# reads devicetree/DMI because those are available in a minimal guest.
PLATFORM_KIND="unknown"
PLATFORM_MODEL=""
PLATFORM_CHASSIS=""
detect_platform() {
  local model product compatible chassis
  model=$(read_value "$SYSFS/firmware/devicetree/base/model")
  compatible=$(read_value "$SYSFS/firmware/devicetree/base/compatible")
  product=$(read_value "$SYSFS/class/dmi/id/product_name")
  chassis=$(read_value "$SYSFS/class/dmi/id/chassis_type")

  PLATFORM_MODEL="${model:-${product:-unknown}}"
  PLATFORM_CHASSIS="$chassis"

  case " ${model} ${product} ${compatible} " in
    *QEMU* | *qemu* | *KVM* | *kvm* | *VirtualBox* | *VMware* | *Bochs*)
      PLATFORM_KIND="qemu"
      return 0
      ;;
    *PinePhone* | *pinephone* | *Pine64* | *pine64* | *Librem* | *librem*)
      PLATFORM_KIND="phone"
      return 0
      ;;
  esac

  case "$chassis" in
    8 | 9 | 10 | 14) PLATFORM_KIND="laptop" ;;
    30 | 31 | 32) PLATFORM_KIND="tablet" ;;
    3 | 4 | 5 | 6 | 7 | 15 | 16) PLATFORM_KIND="desktop" ;;
    "")
      if [ -n "$model" ] || [ -n "$compatible" ]; then
        PLATFORM_KIND="arm-device"
      else
        PLATFORM_KIND="unknown"
      fi
      ;;
    *) PLATFORM_KIND="unknown" ;;
  esac
}

BATTERY_NAMES=()
BATTERY_STATUS=()
BATTERY_PRESENT=()
BATTERY_CAPACITY=()
BATTERY_HEALTH=()
BATTERY_TECHNOLOGY=()
BATTERY_MODEL=()
BATTERY_VOLTAGE_UV=()
BATTERY_CURRENT_UA=()
BATTERY_POWER_UW=()
BATTERY_TEMP_C=()
BATTERY_CYCLE_COUNT=()
BATTERY_THRESHOLD_START=()
BATTERY_THRESHOLD_END=()
BATTERY_THRESHOLD_BEHAVIOUR=()
BATTERY_THRESHOLD_LIMIT=()
BATTERY_THRESHOLD_SUPPORTED=()
AC_ONLINE=false
BATTERY_CHARGING=false

collect_power_supplies() {
  local dir type_lc present status capacity health technology model
  local voltage current power temp cycle start end behaviour limit supported
  local value

  for dir in "$SYSFS"/class/power_supply/*; do
    [ -d "$dir" ] || continue
    type_lc=$(read_value "$dir/type")
    type_lc=${type_lc,,}

    case "$type_lc" in
      battery)
        present=$(read_value "$dir/present")
        [ -n "$present" ] || present="1"
        status=$(read_value "$dir/status")
        [ -n "$status" ] || status="Unknown"
        capacity=$(read_value "$dir/capacity")
        health=$(read_value "$dir/health")
        technology=$(read_value "$dir/technology")
        model=$(read_value "$dir/model_name")
        [ -n "$model" ] || model=$(read_value "$dir/model")
        voltage=$(read_value "$dir/voltage_now")
        current=$(read_value "$dir/current_now")
        power=$(read_value "$dir/power_now")
        temp=$(read_value "$dir/temp")
        cycle=$(read_value "$dir/cycle_count")
        start=$(read_value "$dir/charge_control_start_threshold")
        end=$(read_value "$dir/charge_control_end_threshold")
        behaviour=$(read_value "$dir/charge_behaviour")
        limit=$(read_value "$dir/charge_control_limit")

        # "supported" means the helper can apply a start/end window. A device
        # that only exposes charge_behaviour or charge_control_limit is
        # reported below but is not treated as a writable threshold target.
        supported=false
        if [ -n "$start" ] || [ -n "$end" ]; then
          supported=true
        fi

        BATTERY_NAMES+=("$(basename "$dir")")
        BATTERY_STATUS+=("$status")
        BATTERY_PRESENT+=("$present")
        BATTERY_CAPACITY+=("$capacity")
        BATTERY_HEALTH+=("$health")
        BATTERY_TECHNOLOGY+=("$technology")
        BATTERY_MODEL+=("$model")
        BATTERY_VOLTAGE_UV+=("$voltage")
        BATTERY_CURRENT_UA+=("$current")
        BATTERY_POWER_UW+=("$power")
        BATTERY_CYCLE_COUNT+=("$cycle")
        BATTERY_THRESHOLD_START+=("$start")
        BATTERY_THRESHOLD_END+=("$end")
        BATTERY_THRESHOLD_BEHAVIOUR+=("$behaviour")
        BATTERY_THRESHOLD_LIMIT+=("$limit")
        BATTERY_THRESHOLD_SUPPORTED+=("$supported")

        case "$status" in
          Charging | Full | Fully\ charged | PendingCharge) BATTERY_CHARGING=true ;;
        esac

        if is_uint "$temp"; then
          # power_supply temperature is tenths of a degree Celsius.
          BATTERY_TEMP_C+=("$(awk -v t="$temp" 'BEGIN { printf "%.1f", t / 10 }')")
        else
          BATTERY_TEMP_C+=("")
        fi
        ;;
      mains | usb | usb_c | usb-c | wireless)
        value=$(read_value "$dir/online")
        if [ "$value" = "1" ]; then
          AC_ONLINE=true
        fi
        ;;
    esac
  done
}

THERMAL_ZONES=()
THERMAL_TEMPS=()
THERMAL_SOURCES=()
collect_thermal() {
  local file zone raw type temp

  for file in "$SYSFS"/class/thermal/thermal_zone*/temp; do
    [ -r "$file" ] || continue
    zone=${file%/temp}
    zone=${zone##*/}
    type=$(read_value "${file%/temp}/type")
    [ -n "$type" ] || type="$zone"
    raw=$(read_value "$file")
    is_uint "$raw" || [[ "$raw" =~ ^-?[0-9]+$ ]] || continue
    temp=$(awk -v t="$raw" 'BEGIN {
      if (t > 1000 || t < -1000) printf "%.1f", t / 1000;
      else printf "%.1f", t;
    }')
    THERMAL_ZONES+=("$type")
    THERMAL_TEMPS+=("$temp")
    THERMAL_SOURCES+=("thermal")
  done

  # hwmon is a fallback for systems without thermal zones. Do not duplicate
  # readings when both interfaces describe the same sensor.
  if [ "${#THERMAL_ZONES[@]}" -eq 0 ]; then
    for file in "$SYSFS"/class/hwmon/hwmon*/temp*_input; do
      [ -r "$file" ] || continue
      raw=$(read_value "$file")
      is_uint "$raw" || [[ "$raw" =~ ^-?[0-9]+$ ]] || continue
      zone=${file%/temp*_input}
      zone=${zone##*/}
      type=$(read_value "${file%_input}_label")
      [ -n "$type" ] || type=$(read_value "${file%/*}/name")
      [ -n "$type" ] || type="$zone"
      temp=$(awk -v t="$raw" 'BEGIN {
        if (t > 1000 || t < -1000) printf "%.1f", t / 1000;
        else printf "%.1f", t;
      }')
      THERMAL_ZONES+=("$type")
      THERMAL_TEMPS+=("$temp")
      THERMAL_SOURCES+=("hwmon")
    done
  fi
}

SUSPEND_STATES=""
MEM_SLEEP=""
SUSPEND_SUPPORTED=false
WAKEUP_ENABLED=0
collect_suspend() {
  local file
  SUSPEND_STATES=$(read_value "$SYSFS/power/state")
  MEM_SLEEP=$(read_value "$SYSFS/power/mem_sleep")
  case " $SUSPEND_STATES " in
    *" mem "*) SUSPEND_SUPPORTED=true ;;
    *" freeze "*) SUSPEND_SUPPORTED=true ;;
  esac

  for file in "$SYSFS"/class/wakeup/*/power/wakeup; do
    [ -r "$file" ] || continue
    if [ "$(read_value "$file")" = "enabled" ]; then
      WAKEUP_ENABLED=$((WAKEUP_ENABLED + 1))
    fi
  done
}

WARNINGS=()
build_warnings() {
  local i status capacity temp

  if [ "${#BATTERY_NAMES[@]}" -eq 0 ]; then
    WARNINGS+=("No battery is exposed by this kernel; AC-only or virtual machine.")
  fi

  for i in "${!BATTERY_NAMES[@]}"; do
    status=${BATTERY_STATUS[$i]}
    capacity=${BATTERY_CAPACITY[$i]}
    is_uint "$capacity" || continue
    case "$status" in
      Charging | Full | Fully\ charged)
        ;;
      *)
        if [ "$capacity" -le 5 ]; then
          WARNINGS+=("${BATTERY_NAMES[$i]} is critically low at ${capacity}%.")
        elif [ "$capacity" -le 20 ]; then
          WARNINGS+=("${BATTERY_NAMES[$i]} is low at ${capacity}%.")
        fi
        ;;
    esac
  done

  for i in "${!THERMAL_ZONES[@]}"; do
    temp=${THERMAL_TEMPS[$i]}
    if awk -v t="$temp" -v c="$POWER_THERMAL_CRITICAL_C" 'BEGIN { exit !(t >= c) }'; then
      WARNINGS+=("${THERMAL_ZONES[$i]} is at ${temp} C, at or above the critical policy threshold ${POWER_THERMAL_CRITICAL_C} C.")
    elif awk -v t="$temp" -v w="$POWER_THERMAL_WARN_C" 'BEGIN { exit !(t >= w) }'; then
      WARNINGS+=("${THERMAL_ZONES[$i]} is at ${temp} C, at or above the warning threshold ${POWER_THERMAL_WARN_C} C.")
    fi
  done

  if [ "$SUSPEND_SUPPORTED" = false ]; then
    WARNINGS+=("The kernel exposes no mem/freeze suspend state; suspend testing is not possible in this guest.")
  fi

  case "$PLATFORM_KIND" in
    laptop | desktop | tablet)
      WARNINGS+=("A ${PLATFORM_KIND} chassis was detected; do not run the suspend test here.")
      ;;
    unknown)
      WARNINGS+=("Platform could not be classified; refuse suspend testing outside QEMU or a supported phone.")
      ;;
  esac
}

print_text() {
  local i status present external="no" charging="no"
  local start end behaviour limit

  printf 'Maria Padilha power diagnostic\n'
  printf 'read-only: true (one scan; no daemon, timer or threshold write)\n'
  printf '\n== platform ==\n'
  printf 'kind: %s\n' "$PLATFORM_KIND"
  printf 'model: %s\n' "$PLATFORM_MODEL"
  if [ -n "$PLATFORM_CHASSIS" ]; then
    printf 'chassis_type: %s\n' "$PLATFORM_CHASSIS"
  fi

  printf '\n== power supply ==\n'
  if [ "$AC_ONLINE" = true ] || [ "$BATTERY_CHARGING" = true ]; then external="yes"; fi
  printf 'external_power: %s\n' "$external"
  if [ "${#BATTERY_NAMES[@]}" -eq 0 ]; then
    printf 'battery: none exposed\n'
  fi
  for i in "${!BATTERY_NAMES[@]}"; do
    status=${BATTERY_STATUS[$i]}
    present=${BATTERY_PRESENT[$i]}
    charging="no"
    case "$status" in
      Charging | Full | Fully\ charged | PendingCharge) charging="yes" ;;
    esac
    printf 'battery %s: present=%s status=%s capacity=%s%% charging=%s\n' \
      "${BATTERY_NAMES[$i]}" "$present" "$status" \
      "${BATTERY_CAPACITY[$i]:-unknown}" "$charging"
    if [ -n "${BATTERY_HEALTH[$i]}" ]; then
      printf '  health=%s technology=%s model=%s\n' \
        "${BATTERY_HEALTH[$i]}" "${BATTERY_TECHNOLOGY[$i]:-unknown}" "${BATTERY_MODEL[$i]:-unknown}"
    fi
    if [ -n "${BATTERY_TEMP_C[$i]}" ]; then
      printf '  temperature=%s C\n' "${BATTERY_TEMP_C[$i]}"
    fi
    if [ -n "${BATTERY_VOLTAGE_UV[$i]}" ]; then
      printf '  voltage_now=%s uV\n' "${BATTERY_VOLTAGE_UV[$i]}"
    fi
    if [ -n "${BATTERY_CURRENT_UA[$i]}" ]; then
      printf '  current_now=%s uA\n' "${BATTERY_CURRENT_UA[$i]}"
    fi
    if [ -n "${BATTERY_POWER_UW[$i]}" ]; then
      printf '  power_now=%s uW\n' "${BATTERY_POWER_UW[$i]}"
    fi
    if [ -n "${BATTERY_CYCLE_COUNT[$i]}" ]; then
      printf '  cycle_count=%s\n' "${BATTERY_CYCLE_COUNT[$i]}"
    fi

    start=${BATTERY_THRESHOLD_START[$i]}
    end=${BATTERY_THRESHOLD_END[$i]}
    behaviour=${BATTERY_THRESHOLD_BEHAVIOUR[$i]}
    limit=${BATTERY_THRESHOLD_LIMIT[$i]}
    printf '  charge_thresholds: supported=%s' "${BATTERY_THRESHOLD_SUPPORTED[$i]}"
    if [ -n "$start" ]; then printf ' start=%s' "$start"; fi
    if [ -n "$end" ]; then printf ' end=%s' "$end"; fi
    if [ -n "$behaviour" ]; then printf ' behaviour=%s' "$behaviour"; fi
    if [ -n "$limit" ]; then printf ' limit=%s' "$limit"; fi
    printf '\n'
  done

  printf '\n== charge threshold policy ==\n'
  printf 'mode: %s\n' "$POWER_CHARGE_THRESHOLD_MODE"
  printf 'desired: start=%s%% end=%s%%\n' "$POWER_CHARGE_THRESHOLD_START" "$POWER_CHARGE_THRESHOLD_END"
  printf 'note: unsupported hardware is a no-op; this diagnostic never writes.\n'

  printf '\n== thermal ==\n'
  if [ "${#THERMAL_ZONES[@]}" -eq 0 ]; then
    printf 'zones: none exposed\n'
  fi
  for i in "${!THERMAL_ZONES[@]}"; do
    printf '%s: %s C (%s)\n' "${THERMAL_ZONES[$i]}" "${THERMAL_TEMPS[$i]}" "${THERMAL_SOURCES[$i]}"
  done
  printf 'policy: warn=%s C critical=%s C\n' "$POWER_THERMAL_WARN_C" "$POWER_THERMAL_CRITICAL_C"

  printf '\n== suspend ==\n'
  printf 'states: %s\n' "${SUSPEND_STATES:-none}"
  printf 'mem_sleep: %s\n' "${MEM_SLEEP:-none}"
  printf 'supported: %s\n' "$SUSPEND_SUPPORTED"
  printf 'policy: %s\n' "$POWER_SUSPEND_POLICY"
  printf 'hibernate_allowed: %s\n' "$POWER_SUSPEND_ALLOW_HIBERNATE"
  printf 'wakeup_enabled: %s\n' "$WAKEUP_ENABLED"
  printf 'note: this diagnostic never suspends; see docs/qemu-power-checklist.md.\n'

  printf '\n== warnings ==\n'
  if [ "${#WARNINGS[@]}" -eq 0 ]; then
    printf 'none\n'
  else
    for i in "${!WARNINGS[@]}"; do
      printf '%s. %s\n' "$((i + 1))" "${WARNINGS[$i]}"
    done
  fi
}

print_json() {
  local bjson="" tjson="" wjson="" item i
  local start end behaviour limit

  for i in "${!BATTERY_NAMES[@]}"; do
    start=${BATTERY_THRESHOLD_START[$i]}
    end=${BATTERY_THRESHOLD_END[$i]}
    behaviour=${BATTERY_THRESHOLD_BEHAVIOUR[$i]}
    limit=${BATTERY_THRESHOLD_LIMIT[$i]}
    item=$(printf '{"name":%s,"present":%s,"status":%s,"capacity_percent":%s,"health":%s,"technology":%s,"model":%s,"temperature_c":%s,"voltage_now_uv":%s,"current_now_ua":%s,"power_now_uw":%s,"cycle_count":%s,"charge_thresholds":{"supported":%s,"start":%s,"end":%s,"behaviour":%s,"limit":%s}}' \
      "$(json_string "${BATTERY_NAMES[$i]}")" \
      "$(json_bool "$([ "${BATTERY_PRESENT[$i]}" = "1" ] && printf true || printf false)")" \
      "$(json_string "${BATTERY_STATUS[$i]}")" \
      "$(json_number "${BATTERY_CAPACITY[$i]}")" \
      "$(json_string "${BATTERY_HEALTH[$i]}")" \
      "$(json_string "${BATTERY_TECHNOLOGY[$i]}")" \
      "$(json_string "${BATTERY_MODEL[$i]}")" \
      "$(json_number "${BATTERY_TEMP_C[$i]}")" \
      "$(json_number "${BATTERY_VOLTAGE_UV[$i]}")" \
      "$(json_number "${BATTERY_CURRENT_UA[$i]}")" \
      "$(json_number "${BATTERY_POWER_UW[$i]}")" \
      "$(json_number "${BATTERY_CYCLE_COUNT[$i]}")" \
      "$(json_bool "${BATTERY_THRESHOLD_SUPPORTED[$i]}")" \
      "$(json_number "$start")" \
      "$(json_number "$end")" \
      "$(json_string "$behaviour")" \
      "$(json_number "$limit")")
    bjson="${bjson:+$bjson,}$item"
  done

  for i in "${!THERMAL_ZONES[@]}"; do
    item=$(printf '{"zone":%s,"temperature_c":%s,"source":%s}' \
      "$(json_string "${THERMAL_ZONES[$i]}")" \
      "$(json_number "${THERMAL_TEMPS[$i]}")" \
      "$(json_string "${THERMAL_SOURCES[$i]}")")
    tjson="${tjson:+$tjson,}$item"
  done

  for i in "${!WARNINGS[@]}"; do
    wjson="${wjson:+$wjson,}$(json_string "${WARNINGS[$i]}")"
  done

  printf '{\n'
  printf '  "schema": 1,\n'
  printf '  "read_only": true,\n'
  printf '  "platform": {"kind": %s, "model": %s, "chassis_type": %s},\n' \
    "$(json_string "$PLATFORM_KIND")" "$(json_string "$PLATFORM_MODEL")" "$(json_number "$PLATFORM_CHASSIS")"
  printf '  "paths": {"config": %s, "helper": %s, "service": %s, "sleep_hook": %s},\n' \
    "$(json_string "$POWER_CONFIG_PATH")" \
    "$(json_string "$POWER_CHARGE_THRESHOLD_HELPER")" \
    "$(json_string "$POWER_CHARGE_THRESHOLD_SERVICE")" \
    "$(json_string "$POWER_SLEEP_HOOK_NAME")"
  printf '  "battery": {"count": %d, "external_power": %s, "devices": [%s]},\n' \
    "${#BATTERY_NAMES[@]}" "$(json_bool "$([ "$AC_ONLINE" = true ] || [ "$BATTERY_CHARGING" = true ] && printf true || printf false)")" "$bjson"
  printf '  "charge_threshold_policy": {"mode": %s, "start": %s, "end": %s},\n' \
    "$(json_string "$POWER_CHARGE_THRESHOLD_MODE")" \
    "$(json_number "$POWER_CHARGE_THRESHOLD_START")" \
    "$(json_number "$POWER_CHARGE_THRESHOLD_END")"
  printf '  "thermal": {"zones": [%s], "warn_c": %s, "critical_c": %s},\n' \
    "$tjson" "$(json_number "$POWER_THERMAL_WARN_C")" "$(json_number "$POWER_THERMAL_CRITICAL_C")"
  printf '  "suspend": {"states": %s, "mem_sleep": %s, "supported": %s, "policy": %s, "hibernate_allowed": %s, "hybrid_sleep_allowed": %s, "suspend_then_hibernate_allowed": %s, "idle_action": %s, "wakeup_enabled": %d},\n' \
    "$(json_string "$SUSPEND_STATES")" \
    "$(json_string "$MEM_SLEEP")" \
    "$(json_bool "$SUSPEND_SUPPORTED")" \
    "$(json_string "$POWER_SUSPEND_POLICY")" \
    "$(json_bool "$POWER_SUSPEND_ALLOW_HIBERNATE")" \
    "$(json_bool "$POWER_SUSPEND_ALLOW_HYBRID_SLEEP")" \
    "$(json_bool "$POWER_SUSPEND_ALLOW_SUSPEND_THEN_HIBERNATE")" \
    "$(json_string "$POWER_IDLE_ACTION")" \
    "$WAKEUP_ENABLED"
  printf '  "warnings": [%s]\n' "$wjson"
  printf '}\n'
}

detect_platform
collect_power_supplies
collect_thermal
collect_suspend
build_warnings

if [ "$FORMAT" = "json" ]; then
  print_json
else
  print_text
fi

if [ "$STRICT" = true ] && [ "${#WARNINGS[@]}" -gt 0 ]; then
  exit 1
fi

exit 0
