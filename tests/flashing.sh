#!/usr/bin/env bash
# Flashing documentation and read-only preflight checks.
#
# These checks never invoke sudo, dd, fastboot, pmbootstrap flasher, mount,
# umount, mkfs or a partition tool. They do not touch a block device: the
# preflight is exercised against a regular-file fixture and rejected paths.

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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/padilha-flashing-test.XXXXXX")
fixtures=()
cleanup() {
  local fixture
  for fixture in "${fixtures[@]}"; do
    rm -f -- "$fixture" "$fixture.sha256"
  done
  rm -rf -- "$tmp"
}
trap cleanup EXIT

make_fixture() {
  local path=$1
  printf 'padilha flash preflight fixture\n' >"$path"
  (cd "$ROOT/out" && sha256sum "$(basename -- "$path")" >"$(basename -- "$path").sha256")
  fixtures+=("$path")
}

run_case() {
  local label=$1 expected=$2
  shift 2
  local out="$tmp/$label.out" err="$tmp/$label.err" rc
  set +e
  "$@" >"$out" 2>"$err"
  rc=$?
  set -e
  if [ "$rc" -eq "$expected" ]; then
    ok "$label (exit $rc)"
  else
    bad "$label exited $rc, expected $expected"
    sed 's/^/  /' "$err" >&2
    sed 's/^/  /' "$out" >&2
  fi
}

output_has() {
  local label=$1 needle=$2
  if grep -qF -- "$needle" "$tmp/$label.out" "$tmp/$label.err"; then
    ok "$label output mentions '$needle'"
  else
    bad "$label output does not mention '$needle'"
  fi
}

log "== documentation =="
doc=docs/flashing.md
check_file "$doc"
check_text "$doc" "## Supported-device matrix" "documentation has the supported-device matrix"
check_text "$doc" "## Prerequisites" "documentation lists prerequisites"
check_text "$doc" "## Back up first: data-loss warning" "documentation has backup steps"
check_text "$doc" "## Bootloader unlocking warning" "documentation warns about bootloader unlocking"
check_text "$doc" "## Dry-run/preflight check" "documentation documents the preflight"
check_text "$doc" "## Manual flashing commands (microSD)" "documentation has flashing commands"
check_text "$doc" "## Recovery and unbrick notes" "documentation has recovery notes"
check_text "$doc" "DATA LOSS" "documentation has an explicit data-loss warning"
check_text "$doc" "BOOTLOADER UNLOCK" "documentation has an explicit unlock warning"
check_text "$doc" "scripts/flash-check.sh" "documentation links the preflight script"
check_text "$doc" "sha256sum --check" "documentation verifies the image checksum"
check_text "$doc" "sudo dd if=" "documentation shows the manual write command"
check_text "$doc" "ddrescue" "documentation covers recovery imaging"
check_text "$doc" "eMMC" "documentation states the eMMC scope"
check_text "$doc" "No image has been built for a phone" "documentation does not claim a physical image"
check_text "$doc" "--strict-support" "documentation explains the strict support gate"
check_text "$doc" "Never flash automatically" "documentation forbids automatic flashing"
check_text README.md "docs/flashing.md" "README links the flashing document"

log "== flashing policy =="
# shellcheck source=../config/flashing.conf
. "$ROOT/config/flashing.conf"
[ "$FLASHING_CONFIG_VERSION" = "1" ] &&
  ok "flashing policy version 1" || bad "flashing policy version missing"
[ "$FLASHING_MODE" = "manual-check-only" ] &&
  ok "flashing is manual-check-only" || bad "flashing mode is not manual-check-only"
[ "$FLASHING_AUTOMATIC" = "false" ] &&
  ok "automatic flashing is disabled" || bad "automatic flashing is enabled"
[ "${FLASH_STATUS_qemu_aarch64:-}" = "virtual-only" ] &&
  ok "QEMU is virtual-only" || bad "QEMU status is not virtual-only"
[ "${FLASH_STATUS_pine64_pinephone:-}" = "bring-up" ] &&
  ok "PinePhone is a bring-up candidate, not supported" ||
  bad "PinePhone status must stay bring-up until the physical gate passes"
[ -n "${FLASH_STATUS_pine64_pinephone:-}" ] &&
  [ "${FLASH_STATUS_pine64_pinephone:-}" != "supported" ] &&
  ok "PinePhone is not falsely marked supported" ||
  bad "PinePhone must not be marked supported yet"

log "== preflight script =="
check_file scripts/flash-check.sh
[ -x scripts/flash-check.sh ] &&
  ok "preflight is executable" || bad "preflight is not executable"
bash -n scripts/flash-check.sh &&
  ok "preflight passes bash -n" || bad "preflight has a bash syntax error"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --severity=warning -x scripts/flash-check.sh &&
    ok "preflight passes shellcheck" || bad "preflight fails shellcheck"
else
  log "skip shellcheck (not installed)"
fi

check_text scripts/flash-check.sh "NO WRITE WAS PERFORMED" "preflight states that it does not write"
check_text scripts/flash-check.sh "sha256sum" "preflight verifies SHA-256"
check_text scripts/flash-check.sh "/proc/self/mountinfo" "preflight checks mounted devices"
check_text scripts/flash-check.sh "/proc/swaps" "preflight checks swap"
check_text scripts/flash-check.sh "FLASHING_REQUIRE_REMOVABLE" "preflight enforces removable media"
check_text scripts/flash-check.sh "FLASHING_REQUIRE_WHOLE_DISK" "preflight enforces a whole disk"
check_text scripts/flash-check.sh "FLASHING_REFUSE_READ_ONLY" "preflight enforces writable media"

# There is intentionally no write path. These are command-position matches, so
# documentation strings inside the script do not trip the check.
if grep -nE '^[[:space:]]*(sudo|doas|dd|fastboot|mkfs|mkfs\.[a-z0-9]+|parted|fdisk|sgdisk|mount|umount|blockdev|pmbootstrap[[:space:]]+flasher)([[:space:]]|$)' \
  scripts/flash-check.sh >"$tmp/forbidden.txt"; then
  bad "preflight contains a privileged or write command"
  sed 's/^/  /' "$tmp/forbidden.txt" >&2
else
  ok "preflight contains no privileged or write command"
fi
if grep -nE '^[[:space:]]*(--write|--force|--yes)([[:space:]]|\)|$)' \
  scripts/flash-check.sh >"$tmp/write-options.txt"; then
  bad "preflight exposes a write/force/yes option"
  sed 's/^/  /' "$tmp/write-options.txt" >&2
else
  ok "preflight exposes no write/force/yes option"
fi

log "== preflight behaviour =="
mkdir -p "$ROOT/out"
fixture="$ROOT/out/.flash-test-valid-$$.img"
make_fixture "$fixture"

run_case help 0 scripts/flash-check.sh --help
output_has help "never writes anything"

run_case image-ok 0 scripts/flash-check.sh \
  --device pine64-pinephone --image "$fixture" --image-only
output_has image-ok "NO WRITE WAS PERFORMED"
output_has image-ok "bring-up only"

run_case strict-support 2 scripts/flash-check.sh \
  --device pine64-pinephone --image "$fixture" --image-only --strict-support
output_has strict-support "strict support gate"

run_case no-device 2 scripts/flash-check.sh --image-only
run_case both-modes 2 scripts/flash-check.sh \
  --device pine64-pinephone --image-only --target-only
run_case image-mode-with-target 2 scripts/flash-check.sh \
  --device pine64-pinephone --image-only --target /dev/null
run_case target-mode-with-image 2 scripts/flash-check.sh \
  --device pine64-pinephone --target-only --image "$fixture"
run_case no-target 2 scripts/flash-check.sh \
  --device pine64-pinephone --image "$fixture"
run_case unknown-option 2 scripts/flash-check.sh --device pine64-pinephone --frobnicate

run_case virtual-device 1 scripts/flash-check.sh \
  --device qemu-aarch64 --image "$fixture" --image-only
output_has virtual-device "virtual target"

run_case unknown-device 1 scripts/flash-check.sh \
  --device not-a-real-device --image "$fixture" --image-only

outside_image="$tmp/outside.img"
cp -- "$fixture" "$outside_image"
printf 'outside fixture\n' >"$outside_image"
(cd "$tmp" && sha256sum outside.img >outside.img.sha256)
run_case image-outside-out 1 scripts/flash-check.sh \
  --device pine64-pinephone --image "$outside_image" --image-only
output_has image-outside-out "must stay under"

bad_manifest="$ROOT/out/.flash-test-bad-manifest-$$.img"
printf 'bad manifest fixture\n' >"$bad_manifest"
printf '%064d  %s\n' 0 "$(basename -- "$bad_manifest")" >"$bad_manifest.sha256"
fixtures+=("$bad_manifest")
run_case image-bad-checksum 1 scripts/flash-check.sh \
  --device pine64-pinephone --image "$bad_manifest" --image-only
output_has image-bad-checksum "checksum mismatch"

no_manifest="$ROOT/out/.flash-test-no-manifest-$$.img"
printf 'no manifest fixture\n' >"$no_manifest"
fixtures+=("$no_manifest")
run_case image-no-manifest 1 scripts/flash-check.sh \
  --device pine64-pinephone --image "$no_manifest" --image-only
output_has image-no-manifest "missing checksum manifest"

link_image="$ROOT/out/.flash-test-link-$$.img"
ln -s "$fixture" "$link_image"
fixtures+=("$link_image")
run_case image-symlink 1 scripts/flash-check.sh \
  --device pine64-pinephone --image "$link_image" --image-only
output_has image-symlink "must not be a symlink"

run_case target-outside-dev 1 scripts/flash-check.sh \
  --device pine64-pinephone --target-only --target "$tmp/not-a-device"
output_has target-outside-dev "target must be under /dev/"

run_case target-not-block 1 scripts/flash-check.sh \
  --device pine64-pinephone --target-only --target /dev/null
output_has target-not-block "not an allowed whole-disk node"

run_case full-target-rejected 1 scripts/flash-check.sh \
  --device pine64-pinephone --image "$fixture" --target /dev/null
output_has full-target-rejected "not an allowed whole-disk node"

log "== README and docs cross-checks =="
check_text README.md "make flashing-test" "README lists the flashing test target"
check_text docs/build.md "docs/flashing.md" "build notes link the flashing document"
check_text devices/pine64-pinephone/README.md "docs/flashing.md" "PinePhone notes link the flashing document"

[ "$fail" -eq 0 ]
