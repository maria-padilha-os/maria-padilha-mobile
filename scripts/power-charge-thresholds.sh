#!/usr/bin/env bash
# Apply the configured charge window when the kernel exposes standard
# power_supply threshold attributes.
#
# This helper is normally run once as root from
# maria-padilha-charge-thresholds.service (and after resume). It is safe to run
# as the normal user with --dry-run: that mode only reads sysfs. --apply
# refuses to run without root and never guesses at a vendor-specific interface.
#
# No loop, no daemon, no timer.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_FILE="${POWER_CONFIG_FILE:-/etc/maria-padilha/power.conf}"
if [ ! -f "$CONFIG_FILE" ]; then
  CONFIG_FILE="$ROOT/config/power/power.conf"
fi
SYSFS="${POWER_SYSFS:-/sys}"
APPLY=false
QUIET=false

die() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

log() {
  [ "$QUIET" = true ] || printf '%s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: scripts/power-charge-thresholds.sh [options]

Options:
  --apply         write supported thresholds (requires root)
  --dry-run       print the plan without writing (default)
  --sysfs DIR     read and write under DIR instead of /sys
  --config FILE   read policy from FILE instead of /etc/maria-padilha/power.conf
  --quiet         suppress successful per-attribute lines
  -h, --help      show this help

Only charge_control_start_threshold and charge_control_end_threshold are
written. If neither exists, the helper is a no-op: the hardware does not expose
the standard interface, and no vendor-specific register is touched.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) APPLY=true ;;
    --dry-run) APPLY=false ;;
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
    --quiet) QUIET=true ;;
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
# shellcheck source=/dev/null
. "$CONFIG_FILE"

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

case "$POWER_CHARGE_THRESHOLD_MODE" in
  off)
    log "charge threshold mode is off; nothing to do"
    exit 0
    ;;
  apply-if-supported) ;;
  *)
    die "unknown POWER_CHARGE_THRESHOLD_MODE: $POWER_CHARGE_THRESHOLD_MODE"
    ;;
esac

is_uint "$POWER_CHARGE_THRESHOLD_START" ||
  die "POWER_CHARGE_THRESHOLD_START must be an integer 0..100"
is_uint "$POWER_CHARGE_THRESHOLD_END" ||
  die "POWER_CHARGE_THRESHOLD_END must be an integer 0..100"
[ "$POWER_CHARGE_THRESHOLD_START" -ge 0 ] && [ "$POWER_CHARGE_THRESHOLD_START" -le 100 ] ||
  die "POWER_CHARGE_THRESHOLD_START must be 0..100"
[ "$POWER_CHARGE_THRESHOLD_END" -ge 0 ] && [ "$POWER_CHARGE_THRESHOLD_END" -le 100 ] ||
  die "POWER_CHARGE_THRESHOLD_END must be 0..100"
[ "$POWER_CHARGE_THRESHOLD_START" -lt "$POWER_CHARGE_THRESHOLD_END" ] ||
  die "charge threshold start must be lower than end"

if [ "$APPLY" = true ] && [ "$(id -u)" -ne 0 ]; then
  die "applying charge thresholds requires root; use --dry-run as a normal user"
fi

write_threshold() {
  local file="$1"
  local value="$2"

  case "$file" in
    "$SYSFS"/class/power_supply/*/charge_control_start_threshold | \
      "$SYSFS"/class/power_supply/*/charge_control_end_threshold) ;;
    *) die "refusing to write an unexpected sysfs path: $file" ;;
  esac

  if [ "$APPLY" = true ]; then
    printf '%s\n' "$value" >"$file" ||
      die "cannot write ${file#"$SYSFS"/}"
    log "set ${file#"$SYSFS"/} = $value"
  else
    log "would set ${file#"$SYSFS"/} = $value (current: $(read_value "$file"))"
  fi
}

supported=0
batteries=0
for dir in "$SYSFS"/class/power_supply/*; do
  [ -d "$dir" ] || continue
  type_lc=$(read_value "$dir/type")
  type_lc=${type_lc,,}
  [ "$type_lc" = "battery" ] || continue

  batteries=$((batteries + 1))
  name=$(basename "$dir")
  present=$(read_value "$dir/present")
  [ -n "$present" ] || present="1"
  if [ "$present" != "1" ]; then
    log "$name: battery is not present; skipped"
    continue
  fi

  start_file="$dir/charge_control_start_threshold"
  end_file="$dir/charge_control_end_threshold"
  has_start=false
  has_end=false
  if [ -e "$start_file" ]; then
    has_start=true
  fi
  if [ -e "$end_file" ]; then
    has_end=true
  fi

  behaviour=$(read_value "$dir/charge_behaviour")
  limit=$(read_value "$dir/charge_control_limit")

  if [ "$has_start" = false ] && [ "$has_end" = false ]; then
    log "$name: no standard charge threshold attribute; no-op"
    if [ -n "$behaviour" ]; then
      log "$name: charge_behaviour exposed (${behaviour}); not changed by this helper"
    fi
    if [ -n "$limit" ]; then
      log "$name: charge_control_limit exposed (${limit}); not changed by this helper"
    fi
    continue
  fi

  supported=$((supported + 1))
  current_start=$(read_value "$start_file")
  current_end=$(read_value "$end_file")
  # Keep every intermediate window valid when the policy changes. Raising the
  # start above the current end (or lowering the end below the current start)
  # needs the other bound written first.
  if [ "$has_start" = true ] && [ "$has_end" = true ] &&
    is_uint "$current_start" && is_uint "$current_end" &&
    [ "$POWER_CHARGE_THRESHOLD_START" -ge "$current_end" ]; then
    write_threshold "$end_file" "$POWER_CHARGE_THRESHOLD_END"
    write_threshold "$start_file" "$POWER_CHARGE_THRESHOLD_START"
  elif [ "$has_start" = true ] && [ "$has_end" = true ] &&
    is_uint "$current_start" && is_uint "$current_end" &&
    [ "$POWER_CHARGE_THRESHOLD_END" -le "$current_start" ]; then
    write_threshold "$start_file" "$POWER_CHARGE_THRESHOLD_START"
    write_threshold "$end_file" "$POWER_CHARGE_THRESHOLD_END"
  else
    if [ "$has_start" = true ]; then
      write_threshold "$start_file" "$POWER_CHARGE_THRESHOLD_START"
    fi
    if [ "$has_end" = true ]; then
      write_threshold "$end_file" "$POWER_CHARGE_THRESHOLD_END"
    fi
  fi
done

if [ "$batteries" -eq 0 ]; then
  log "no battery in $SYSFS/class/power_supply; nothing to do"
elif [ "$supported" -eq 0 ]; then
  log "no battery exposes the standard charge threshold interface; no-op"
else
  if [ "$APPLY" = true ]; then
    log "charge thresholds applied to $supported battery device(s)"
  else
    log "dry run complete; no threshold was written"
  fi
fi
