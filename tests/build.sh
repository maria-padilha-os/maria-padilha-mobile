#!/usr/bin/env bash
# Cheapest CI gate for the image scaffold.
#
# Validates configuration, required files, shell syntax, secret hygiene and
# physical-device exclusions, then writes a deterministic checksum of all build
# inputs. It never builds, flashes, mounts or needs root.

set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../scripts/lib.sh
. "$ROOT/scripts/lib.sh"

load_config

log "== config =="
validate_config
[ "$DEVICE_KIND" = "virtual" ] ||
  die "tests/build.sh expects the virtual target (got '$DEVICE_KIND')"
[ "$DEVICE_PHYSICAL" = "false" ] ||
  die "tests/build.sh expects a non-physical target"
ok "QEMU target needs no phone"

log "== required files =="
validate_required_files

log "== shell syntax =="
validate_shell

log "== secrets =="
scan_secrets

log "== flashing is out of scope =="
if grep -nE --binary-files=without-match \
  -e 'pmbootstrap[[:space:]]+flasher' \
  -e '--disk([=[:space:]]|$)' \
  -e '/dev/(sd|mmcblk|loop)' \
  "$ROOT/scripts/build.sh" "$ROOT/scripts/run-qemu.sh" >/dev/null 2>&1; then
  die "build scripts must not partition or flash physical devices"
fi
ok "build scripts never target a block device"

log "== checksum =="
write_build_checksums
verify_build_checksums

# If a previous full build exists, check its image too. A missing artifact is
# not a test failure: CI validates the scaffold without privileged pmbootstrap.
if [ -f "$OUT_DIR/$IMAGE_NAME" ]; then
  checksum_image
else
  ok "no image artifact yet (run scripts/build.sh on a builder with sudo/doas)"
fi

log "all build scaffold checks passed"
