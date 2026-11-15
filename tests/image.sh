#!/usr/bin/env bash
# Checks for the unprivileged QEMU serial smoke test and its CI contract.
#
# This test never downloads an image, starts QEMU or needs KVM. It exercises
# the failure paths with a fake QEMU binary and checks that the checked-in
# workflow only uploads workflow artifacts (never a release).

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../scripts/lib.sh
. "$ROOT/scripts/lib.sh"

load_config
validate_config

fail=0
ok() {
  printf 'ok %s\n' "$*"
}
bad() {
  printf 'FAIL %s\n' "$*" >&2
  fail=1
}
check_text() {
  local file=$1 needle=$2 label=$3
  if grep -qF -- "$needle" "$file"; then
    ok "$label"
  else
    bad "$label"
  fi
}

log "== smoke config =="
[ "$SMOKE_CONFIG_VERSION" = "1" ] && ok "smoke config version" || bad "smoke config version"
[ "$SMOKE_ARCH" = "aarch64" ] && ok "smoke guest is aarch64" || bad "smoke guest is aarch64"
[[ "$SMOKE_KERNEL_SHA256" =~ ^[0-9a-f]{64}$ ]] &&
  ok "kernel is pinned by sha256" || bad "kernel is pinned by sha256"
[[ "$SMOKE_ROOTFS_SHA256" =~ ^[0-9a-f]{64}$ ]] &&
  ok "rootfs is pinned by sha256" || bad "rootfs is pinned by sha256"
[ "$SMOKE_ARTIFACT_BUDGET_MIB" -le 32 ] &&
  ok "artifact size budget is explicit" || bad "artifact size budget is explicit"
[ "$SMOKE_BOOT_TIME_BUDGET" -le 300 ] &&
  ok "boot time budget is explicit" || bad "boot time budget is explicit"

log "== guest marker and isolation =="
check_text "$ROOT/config/smoke/init.sh" "$SMOKE_MARKER" "guest init prints the known marker"
check_text "$ROOT/scripts/qemu-smoke.sh" "rdinit=/init" "guest init is selected by kernel cmdline"
if grep -qE --binary-files=without-match \
  -e 'pmbootstrap[[:space:]]+flasher' \
  -e 'fastboot' \
  -e '/dev/(sd|mmcblk|loop)' \
  -e '--disk([=[:space:]]|$)' \
  "$ROOT/scripts/build-smoke-rootfs.sh" "$ROOT/scripts/qemu-smoke.sh"; then
  bad "smoke scripts never target a block device"
else
  ok "smoke scripts never target a block device"
fi
check_text "$ROOT/scripts/qemu-smoke.sh" "-nic none" "QEMU guest has no network interface"
check_text "$ROOT/scripts/qemu-smoke.sh" "-display none" "QEMU guest has no display"

log "== CI contract =="
workflow="$ROOT/.github/workflows/ci.yml"
check_text "$workflow" "scripts/build-smoke-rootfs.sh" "CI builds the smoke rootfs"
check_text "$workflow" "scripts/qemu-smoke.sh" "CI runs the serial smoke boot"
check_text "$workflow" "actions/cache@v4" "CI caches pinned downloads"
check_text "$workflow" "actions/upload-artifact@v4" "CI uploads artifacts"
check_text "$workflow" "if-no-files-found: warn" "CI uploads a failure log when the boot fails"
check_text "$ROOT/docs/ci.md" "MARIA_PADILHA_QEMU_SMOKE_OK" "CI docs name the serial marker"
check_text "$ROOT/docs/ci.md" "32 MiB" "CI docs document the artifact budget"
check_text "$ROOT/docs/ci.md" "300 s" "CI docs document the TCG boot budget"
check_text "$ROOT/docs/ci.md" "FAIL KVM" "CI docs document fail-fast KVM behaviour"
check_text "$ROOT/docs/ci.md" "No release publication" "CI docs forbid release publication"
if grep -qE --binary-files=without-match \
  -e 'softprops/action-gh-release' \
  -e 'actions/create-release' \
  -e 'gh[[:space:]]+release' \
  -e 'pmbootstrap[[:space:]]+flasher' \
  -e 'fastboot' \
  -e '/dev/(sd|mmcblk|loop)' \
  "$workflow"; then
  bad "CI does not publish releases or flash devices"
else
  ok "CI does not publish releases or flash devices"
fi

log "== deterministic cpio =="
tmp="$ROOT/.scratch/image-test.$$"
cleanup() {
  rm -rf -- "$tmp"
}
trap cleanup EXIT
mkdir -p -- "$tmp/root/bin" "$tmp/root/etc"
printf '#!/bin/busybox sh\necho %s\n' "$SMOKE_MARKER" >"$tmp/root/init"
chmod 0755 "$tmp/root/init"
printf 'payload\n' >"$tmp/root/etc/marker"
ln -s marker "$tmp/root/etc/marker-link"
python3 "$ROOT/scripts/smoke-cpio.py" --root "$tmp/root" --output "$tmp/one.cpio.gz"
python3 "$ROOT/scripts/smoke-cpio.py" --root "$tmp/root" --output "$tmp/two.cpio.gz"
if cmp -s "$tmp/one.cpio.gz" "$tmp/two.cpio.gz"; then
  ok "cpio packing is byte-for-byte deterministic"
else
  bad "cpio packing is byte-for-byte deterministic"
fi
if python3 - "$tmp/one.cpio.gz" <<'PY'
import gzip
import sys

with gzip.open(sys.argv[1], "rb") as archive:
    data = archive.read()
offset = 0
names = []
while True:
    assert data[offset:offset + 6] == b"070701", "bad newc magic at %d" % offset
    header = data[offset:offset + 110]
    assert len(header) == 110, "short newc header"
    namesize = int(header[94:102], 16)
    datasize = int(header[54:62], 16)
    name_start = offset + 110
    name = data[name_start:name_start + namesize - 1]
    names.append(name)
    next_offset = name_start + namesize
    next_offset = (next_offset + 3) & ~3
    next_offset = (next_offset + datasize + 3) & ~3
    if name == b"TRAILER!!!":
        break
    offset = next_offset
assert b"init" in names, "missing init"
assert b"etc/marker-link" in names, "missing symlink"
PY
then
  ok "newc archive is aligned and contains init, symlink and trailer"
else
  bad "newc archive is aligned and contains init, symlink and trailer"
fi

log "== KVM fail-fast and bounded TCG =="
printf 'kernel\n' >"$tmp/kernel"
printf 'initramfs\n' >"$tmp/initramfs"
(cd "$tmp" && sha256sum kernel >kernel.sha256 && sha256sum initramfs >initramfs.sha256)
cat >"$tmp/fake-qemu" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "QEMU emulator version 9.0.0"
  exit 0
fi
if [ "${1:-}" = "-accel" ] && [ "${2:-}" = "help" ]; then
  echo "tcg"
  exit 0
fi
echo "MARIA_PADILHA_QEMU_SMOKE_OK"
exit 0
EOF
chmod 0755 "$tmp/fake-qemu"

set +e
kvm_output=$(PADILHA_KVM_DEVICE="$tmp/no-kvm" \
  PADILHA_SMOKE_QEMU_BINARY="$tmp/fake-qemu" \
  "$ROOT/scripts/qemu-smoke.sh" \
  --kernel "$tmp/kernel" --initrd "$tmp/initramfs" \
  --log "$tmp/kvm.log" --budget 5 2>&1)
kvm_rc=$?
set -e
if [ "$kvm_rc" -ne 0 ] && printf '%s\n' "$kvm_output" | grep -qF 'FAIL KVM acceleration is unavailable'; then
  ok "missing KVM fails fast with a clear message"
else
  printf '%s\n' "$kvm_output" >&2
  bad "missing KVM fails fast with a clear message"
fi

set +e
tcg_output=$(PADILHA_KVM_DEVICE="$tmp/no-kvm" \
  PADILHA_SMOKE_QEMU_BINARY="$tmp/fake-qemu" \
  "$ROOT/scripts/qemu-smoke.sh" \
  --kernel "$tmp/kernel" --initrd "$tmp/initramfs" \
  --log "$tmp/tcg.log" --accel tcg --budget 10 2>&1)
tcg_rc=$?
set -e
if [ "$tcg_rc" -eq 0 ] && grep -qF "$SMOKE_MARKER" "$tmp/tcg.log"; then
  ok "explicit TCG path accepts the serial marker"
else
  printf '%s\n' "$tcg_output" >&2
  bad "explicit TCG path accepts the serial marker"
fi

rm -f -- "$tmp/initramfs.sha256"
set +e
missing_output=$(PADILHA_KVM_DEVICE="$tmp/no-kvm" \
  PADILHA_SMOKE_QEMU_BINARY="$tmp/fake-qemu" \
  "$ROOT/scripts/qemu-smoke.sh" \
  --kernel "$tmp/kernel" --initrd "$tmp/initramfs" \
  --log "$tmp/missing.log" --accel tcg --budget 5 2>&1)
missing_rc=$?
set -e
if [ "$missing_rc" -ne 0 ] && printf '%s\n' "$missing_output" | grep -qF 'missing checksum'; then
  ok "boot refuses an unchecked initramfs"
else
  printf '%s\n' "$missing_output" >&2
  bad "boot refuses an unchecked initramfs"
fi

[ "$fail" -eq 0 ]
