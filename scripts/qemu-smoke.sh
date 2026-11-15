#!/usr/bin/env bash
# Boot the minimal smoke rootfs and require a known serial marker.
#
# This helper is intentionally strict about acceleration. The default is
# --accel auto: use KVM when the guest can run natively, otherwise fail before
# QEMU starts with an actionable message. CI on an x86_64 runner explicitly
# opts into bounded TCG because KVM cannot accelerate an aarch64 guest there.
# The boot is always bounded by a wall-clock budget; it can never wait forever.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
. "$ROOT/scripts/lib.sh"

KERNEL_INPUT=""
INITRD_INPUT=""
LOG_INPUT=""
ACCEL="auto"
BUDGET=""
MARKER=""

usage() {
  cat <<'EOF'
Usage: scripts/qemu-smoke.sh [options]

Options:
  --kernel FILE    kernel image (default: out/smoke/vmlinuz-virt)
  --initrd FILE    initramfs image (default: out/smoke/maria-padilha-smoke-aarch64.initramfs.gz)
  --log FILE       serial log (default: out/smoke/qemu-smoke.log)
  --accel MODE     auto (default), kvm or tcg
  --allow-tcg      alias for --accel tcg
  --budget SECONDS hard boot timeout (default: TCG/KVM budget from config)
  --marker TEXT    required serial marker (default: config marker)
  -h, --help       show this help

--accel auto uses KVM only when the guest architecture matches the host and
/dev/kvm is usable. It fails clearly when KVM is unavailable instead of
silently falling back to emulation. Pass --accel tcg to opt into bounded TCG.

Both images must have a matching .sha256 next to them. No block device, network
interface, display server or physical device is attached to the guest.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kernel)
      [ "$#" -ge 2 ] || die "--kernel needs a file"
      KERNEL_INPUT="$2"
      shift
      ;;
    --initrd | --initramfs)
      [ "$#" -ge 2 ] || die "$1 needs a file"
      INITRD_INPUT="$2"
      shift
      ;;
    --log)
      [ "$#" -ge 2 ] || die "--log needs a file"
      LOG_INPUT="$2"
      shift
      ;;
    --accel)
      [ "$#" -ge 2 ] || die "--accel needs auto, kvm or tcg"
      ACCEL="$2"
      shift
      ;;
    --allow-tcg) ACCEL="tcg" ;;
    --budget)
      [ "$#" -ge 2 ] || die "--budget needs seconds"
      BUDGET="$2"
      shift
      ;;
    --marker)
      [ "$#" -ge 2 ] || die "--marker needs text"
      MARKER="$2"
      shift
      ;;
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

load_config
validate_config

case "$ACCEL" in
  auto | kvm | tcg) ;;
  *) die "--accel must be auto, kvm or tcg (got '$ACCEL')" ;;
esac

KERNEL_FILE="${KERNEL_INPUT:-$SMOKE_OUT_DIR/$SMOKE_KERNEL_NAME}"
INITRD_FILE="${INITRD_INPUT:-$SMOKE_OUT_DIR/$SMOKE_INITRAMFS_NAME}"
LOG_FILE="${LOG_INPUT:-$SMOKE_OUT_DIR/$SMOKE_BOOT_LOG}"
MARKER="${MARKER:-$SMOKE_MARKER}"
kvm_device="${PADILHA_KVM_DEVICE:-/dev/kvm}"
host_arch=$(uname -m)

abs_path() {
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

KERNEL_FILE=$(abs_path "$KERNEL_FILE")
INITRD_FILE=$(abs_path "$INITRD_FILE")
LOG_FILE=$(abs_path "$LOG_FILE")
case "$LOG_FILE" in
  "$ROOT"/*) ;;
  *) die "serial log must stay inside $ROOT: $LOG_FILE" ;;
esac

require_command python3
require_command sha256sum
require_command stat

verify_artifact() {
  local label="$1" file="$2" checksum
  [ -f "$file" ] || die "missing $label: $file (run scripts/build-smoke-rootfs.sh)"
  checksum="$file.sha256"
  [ -f "$checksum" ] ||
    die "missing checksum for $label: $checksum (refusing to boot an unchecked artifact)"
  (cd "$(dirname -- "$file")" && sha256sum --check --quiet "$(basename -- "$checksum")") ||
    die "$label checksum does not match $(basename -- "$checksum")"
  ok "$label checksum verifies"
}

verify_artifact "kernel" "$KERNEL_FILE"
verify_artifact "initramfs" "$INITRD_FILE"

PADILHA_QEMU_BINARY="${PADILHA_SMOKE_QEMU_BINARY:-$SMOKE_QEMU_BINARY}"
export PADILHA_QEMU_BINARY
check_qemu_binary

kvm_unavailable_reason() {
  case "$SMOKE_ARCH:$host_arch" in
    aarch64:aarch64 | aarch64:arm64 | x86_64:x86_64 | x86_64:amd64) ;;
    *)
      printf 'guest %s on host %s needs cross-architecture emulation\n' \
        "$SMOKE_ARCH" "$host_arch"
      return 0
      ;;
  esac
  if [ ! -e "$kvm_device" ]; then
    printf '%s does not exist\n' "$kvm_device"
    return 0
  fi
  if [ ! -r "$kvm_device" ] || [ ! -w "$kvm_device" ]; then
    printf '%s is not readable and writable by this user\n' "$kvm_device"
    return 0
  fi
  if ! "$PADILHA_QEMU_BINARY" -accel help 2>/dev/null | grep -qw kvm; then
    printf 'this %s build does not advertise the kvm accelerator\n' "$PADILHA_QEMU_BINARY"
    return 0
  fi
  return 1
}

if reason=$(kvm_unavailable_reason); then
  if [ "$ACCEL" = "auto" ] || [ "$ACCEL" = "kvm" ]; then
    printf 'FAIL KVM acceleration is unavailable: %s\n' "$reason" >&2
    printf 'FAIL refusing to fall back to unbounded TCG; use --accel tcg for a bounded emulated boot\n' >&2
    exit 1
  fi
  log "KVM unused by explicit request: $reason"
else
  if [ "$ACCEL" = "tcg" ]; then
    log "KVM is available but --accel tcg was requested"
  else
    ACCEL="kvm"
  fi
fi

if [ -z "$BUDGET" ]; then
  if [ "$ACCEL" = "kvm" ]; then
    BUDGET="$SMOKE_KVM_BOOT_TIME_BUDGET"
  else
    BUDGET="$SMOKE_BOOT_TIME_BUDGET"
  fi
fi
[[ "$BUDGET" =~ ^[0-9]+$ ]] && [ "$BUDGET" -gt 0 ] ||
  die "boot budget must be a positive integer (got '$BUDGET')"

cmd=(
  "$PADILHA_QEMU_BINARY"
  -machine "$SMOKE_QEMU_MACHINE"
  -m "$SMOKE_QEMU_MEMORY"
  -smp 2
  -kernel "$KERNEL_FILE"
  -initrd "$INITRD_FILE"
  -append "console=$SMOKE_CONSOLE,115200 rdinit=/init panic=1"
  -display none
  -serial stdio
  -monitor none
  -no-reboot
  -nic none
)
if [ "$ACCEL" = "kvm" ]; then
  cmd+=(-accel kvm -cpu "$SMOKE_QEMU_CPU_KVM")
else
  cmd+=(-accel "tcg,thread=multi" -cpu "$SMOKE_QEMU_CPU_TCG")
fi

mkdir -p -- "$(dirname -- "$LOG_FILE")" || die "cannot create serial log directory"
: >"$LOG_FILE" || die "cannot write serial log: $LOG_FILE"

qemu_pid=""
cleanup() {
  if [ -n "$qemu_pid" ] && kill -0 "$qemu_pid" 2>/dev/null; then
    kill -TERM "$qemu_pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

log "acceleration: $ACCEL; hard boot budget: ${BUDGET}s"
log "serial log: $LOG_FILE"
log "running: ${cmd[*]}"
"${cmd[@]}" >>"$LOG_FILE" 2>&1 &
qemu_pid=$!

found=false
waited=0
while [ "$waited" -lt "$BUDGET" ]; do
  if grep -qF -- "$MARKER" "$LOG_FILE" 2>/dev/null; then
    found=true
    break
  fi
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

if [ "$found" = true ]; then
  # The init powers the guest off. Give it a short grace period, then stop
  # QEMU so a broken poweroff path cannot hold the CI job open.
  grace=0
  while kill -0 "$qemu_pid" 2>/dev/null && [ "$grace" -lt 5 ]; do
    sleep 1
    grace=$((grace + 1))
  done
  if kill -0 "$qemu_pid" 2>/dev/null; then
    kill -TERM "$qemu_pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$qemu_pid" 2>/dev/null || true
  fi
  wait "$qemu_pid" 2>/dev/null || true
  qemu_pid=""
  ok "serial marker '$MARKER' seen after ${waited}s"
  exit 0
fi

if kill -0 "$qemu_pid" 2>/dev/null; then
  kill -TERM "$qemu_pid" 2>/dev/null || true
  sleep 1
  kill -KILL "$qemu_pid" 2>/dev/null || true
  wait "$qemu_pid" 2>/dev/null || true
  qemu_pid=""
  die "QEMU did not print '$MARKER' within ${BUDGET}s; see $LOG_FILE"
fi

qemu_status=0
wait "$qemu_pid" || qemu_status=$?
qemu_pid=""
die "QEMU exited with status $qemu_status before printing '$MARKER'; see $LOG_FILE"
