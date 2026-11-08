# shellcheck shell=bash
# Shared helpers for the Maria Padilha Mobile image scaffold.
#
# Callers must set ROOT to the repository checkout before sourcing this file.

die() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*"
}

ok() {
  printf 'ok %s\n' "$*"
}

load_config() {
  local root="${ROOT:?ROOT must be set before load_config}"
  local requested="${DEVICE_OVERRIDE:-}"

  [ -f "$root/config/build.conf" ] ||
    die "missing config/build.conf"
  # shellcheck source=/dev/null
  . "$root/config/build.conf"

  DEVICE="${requested:-$DEFAULT_DEVICE}"
  case "$DEVICE" in
    "" | *[!a-z0-9-]*)
      die "invalid device name: '$DEVICE' (use devices/<name>/device.conf)"
      ;;
  esac

  DEVICE_CONFIG="$root/devices/$DEVICE/device.conf"
  [ -f "$DEVICE_CONFIG" ] ||
    die "missing device config: $DEVICE_CONFIG"

  local selected="$DEVICE"
  # shellcheck source=/dev/null
  . "$DEVICE_CONFIG"

  [ "$DEVICE" = "$selected" ] ||
    die "device config changed DEVICE from '$selected' to '$DEVICE'"

  case "$BUILD_ROOT" in
    "$root"/.scratch/*) ;;
    *) die "BUILD_ROOT must stay under $root/.scratch" ;;
  esac
  [ "$OUT_DIR" = "$root/out" ] ||
    die "OUT_DIR must be $root/out"

  export ROOT DEVICE DEVICE_CONFIG BUILD_ROOT PMB_WORK PMB_CONFIG
  export TOOLCHAIN_DIR OUT_DIR
}

validate_config() {
  local var
  local required=(
    PADILHA_NAME PADILHA_RELEASE PADILHA_CHANNEL
    DEVICE DEVICE_CONFIG DEVICE_ARCH DEVICE_KIND DEVICE_PHYSICAL
    UI INIT_SYSTEM PMB_KERNEL PMB_BOOT_SIZE IMAGE_SIZE IMAGE_NAME
    PMAPORTS_REPO PMAPORTS_COMMIT
    PMBOOTSTRAP_REPO PMBOOTSTRAP_VERSION PMBOOTSTRAP_COMMIT
    ALPINE_MIRROR PMOS_MIRROR
    BUILD_ROOT PMB_WORK PMB_CONFIG TOOLCHAIN_DIR OUT_DIR
    QEMU_MIN_VERSION QEMU_BOOT_TIMEOUT
    KEYBOARD_CONFIG KEYBOARD_BACKEND KEYBOARD_PACKAGE
    KEYBOARD_LAYOUT_NAME KEYBOARD_LAYOUT_DIR
  )

  for var in "${required[@]}"; do
    [ -n "${!var:-}" ] || die "configuration is missing $var"
  done

  [[ "$PADILHA_RELEASE" =~ ^v[0-9]{2}\.[0-9]{2}$ ]] ||
    die "PADILHA_RELEASE must look like v26.06 (got '$PADILHA_RELEASE')"
  [ "$PADILHA_CHANNEL" = "stable" ] ||
    die "PADILHA_CHANNEL must be stable (got '$PADILHA_CHANNEL')"
  [ "$DEVICE_ARCH" = "aarch64" ] ||
    die "ADR 0001 requires an aarch64 target (got '$DEVICE_ARCH')"
  [ "$UI" = "phosh" ] ||
    die "ADR 0001 selects Phosh (got '$UI')"
  [ "$INIT_SYSTEM" = "systemd" ] ||
    die "ADR 0001 selects systemd for M1 (got '$INIT_SYSTEM')"
  [[ "$PMAPORTS_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
    die "PMAPORTS_COMMIT must be a full 40-character commit hash"
  [[ "$PMBOOTSTRAP_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
    die "PMBOOTSTRAP_COMMIT must be a full 40-character commit hash"
  [[ "$PMBOOTSTRAP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "PMBOOTSTRAP_VERSION must be an exact semver (got '$PMBOOTSTRAP_VERSION')"
  [[ "$IMAGE_SIZE" =~ ^[0-9]+[GM]$ ]] ||
    die "IMAGE_SIZE must be an exact size such as 2G (got '$IMAGE_SIZE')"
  [[ "$PMB_BOOT_SIZE" =~ ^[0-9]+$ ]] ||
    die "PMB_BOOT_SIZE must be an integer in MiB"
  if [ "$DEVICE_KIND" = "virtual" ]; then
    [ -n "${QEMU_MEMORY:-}" ] || die "virtual target is missing QEMU_MEMORY"
    [ -n "${QEMU_CPU:-}" ] || die "virtual target is missing QEMU_CPU"
    [ -n "${QEMU_DISPLAY:-}" ] || die "virtual target is missing QEMU_DISPLAY"
    [[ "$QEMU_MEMORY" =~ ^[0-9]+$ ]] ||
      die "QEMU_MEMORY must be an integer in MiB"
  fi
  [[ "$QEMU_MIN_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] ||
    die "QEMU_MIN_VERSION must look like 8.0"
  [[ "$QEMU_BOOT_TIMEOUT" =~ ^[0-9]+$ ]] ||
    die "QEMU_BOOT_TIMEOUT must be an integer in seconds"
  [ "$DEVICE_PHYSICAL" = "true" ] || [ "$DEVICE_PHYSICAL" = "false" ] ||
    die "DEVICE_PHYSICAL must be true or false"

  # ADR 0002: Squeekboard is the only supported OSK backend in M1. Keeping
  # this check in the shared config gate makes a backend swap an explicit,
  # reviewed change instead of an accidental image difference.
  [ "$KEYBOARD_BACKEND" = "squeekboard" ] ||
    die "ADR 0002 selects Squeekboard (got '$KEYBOARD_BACKEND')"
  [ "$KEYBOARD_PACKAGE" = "squeekboard" ] ||
    die "KEYBOARD_PACKAGE must be squeekboard (got '$KEYBOARD_PACKAGE')"
  [ -f "$ROOT/$KEYBOARD_CONFIG" ] ||
    die "missing keyboard config: $KEYBOARD_CONFIG"
  [ -d "$ROOT/$KEYBOARD_LAYOUT_DIR" ] ||
    die "missing keyboard layout directory: $KEYBOARD_LAYOUT_DIR"

  case "$PMAPORTS_REPO" in https://*) ;; *) die "PMAPORTS_REPO must use https" ;; esac
  case "$PMBOOTSTRAP_REPO" in https://*) ;; *) die "PMBOOTSTRAP_REPO must use https" ;; esac

  # Reject floating container/image references in the files that drive the
  # build. Versioned git commits and mirrors are the only inputs.
  if grep -RInE --binary-files=without-match \
    -e '(:latest([[:space:]]|$)|@latest)' \
    --exclude=lib.sh \
    "$ROOT/config" "$ROOT/devices" "$ROOT/scripts" "$ROOT/Makefile" \
    >/dev/null 2>&1; then
    die "floating image/tag reference found in build inputs"
  fi

  ok "pins: Nura $PADILHA_RELEASE, pmaports ${PMAPORTS_COMMIT:0:12}, pmbootstrap $PMBOOTSTRAP_VERSION (${PMBOOTSTRAP_COMMIT:0:12})"
  ok "target: $DEVICE ($DEVICE_ARCH, $UI, $INIT_SYSTEM)"
}

validate_required_files() {
  local file
  local required=(
    README.md
    Makefile
    config/build.conf
    config/keyboard/keyboard.conf
    config/keyboard/layouts/us.yaml
    config/keyboard/layouts/us_wide.yaml
    config/keyboard/layouts/terminal/us.yaml
    config/keyboard/layouts/terminal/us_wide.yaml
    config/keyboard/layouts/url/us.yaml
    config/keyboard/layouts/url/us_wide.yaml
    config/keyboard/layouts/pin/us.yaml
    config/keyboard/layouts/pin/us_wide.yaml
    docs/base-assumption.md
    docs/build.md
    docs/adr/0002-on-screen-keyboard.md
    docs/keyboard.md
    docs/qemu-keyboard-checklist.md
    devices/qemu-aarch64/device.conf
    devices/qemu-aarch64/README.md
    devices/pine64-pinephone/device.conf
    devices/pine64-pinephone/README.md
    shell/shell.qml
    shell/components/Theme.qml
    shell/palettes/padilha-light.json
    shell/README.md
    scripts/build.sh
    scripts/install-squeekboard.sh
    scripts/lib.sh
    scripts/run-qemu.sh
    tests/all.sh
    tests/build.sh
    tests/keyboard.sh
    tests/shell.sh
    .github/workflows/ci.yml
  )

  for file in "${required[@]}"; do
    [ -f "$ROOT/$file" ] || die "required file missing: $file"
  done

  local executable=(
    scripts/build.sh
    scripts/install-squeekboard.sh
    scripts/run-qemu.sh
    tests/all.sh
    tests/build.sh
    tests/keyboard.sh
    tests/shell.sh
  )
  for file in "${executable[@]}"; do
    [ -x "$ROOT/$file" ] || die "required file is not executable: $file"
  done

  ok "required files and executable bits"
}

validate_shell() {
  local file
  while IFS= read -r -d '' file; do
    bash -n "$file" || die "bash syntax error: ${file#"$ROOT"/}"
  done < <(find "$ROOT" \
    \( -path "$ROOT/.git" -o -path "$ROOT/.scratch" -o -path "$ROOT/out" \) -prune -o \
    -type f -name '*.sh' -print0)

  if command -v shellcheck >/dev/null 2>&1; then
    (cd "$ROOT" && shellcheck --severity=warning -x scripts/*.sh tests/*.sh) ||
      die "shellcheck reported problems"
    ok "bash syntax and shellcheck"
  else
    ok "bash syntax (shellcheck not installed; skipped)"
  fi
}

scan_secrets() {
  local hits
  hits=$(grep -RInE --binary-files=without-match \
    --exclude-dir=.git \
    --exclude-dir=.scratch \
    --exclude-dir=out \
    -e 'sk-[A-Za-z0-9]{20,}' \
    -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
    -e 'github_pat_[A-Za-z0-9_]{20,}' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
    -e '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----' \
    "$ROOT" || true)

  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    die "possible secret in the working tree"
  fi

  local tracked
  tracked=$(git -C "$ROOT" ls-files -- \
    '.env' '**/.env' '**/id_rsa' '**/id_ed25519' '**/*.pem' '**/*.key' 2>/dev/null || true)
  if [ -n "$tracked" ]; then
    printf '%s\n' "$tracked" >&2
    die "sensitive-looking file is tracked"
  fi

  ok "no obvious secrets in the working tree"
}

write_build_checksums() {
  local root="${ROOT:?}"
  local out_dir="${OUT_DIR:?}"
  local tmp="$out_dir/.build-inputs.sha256.$$"

  [ "$out_dir" = "$root/out" ] || die "refusing to write checksum outside $root/out"
  mkdir -p -- "$out_dir" || die "cannot create $out_dir"

  (
    cd "$root" || exit 1
    find config devices scripts Makefile README.md -type f -print0 |
      LC_ALL=C sort -z |
      xargs -0 sha256sum --
  ) >"$tmp" || die "failed to checksum build inputs"

  mv -f -- "$tmp" "$out_dir/build-inputs.sha256"
  (cd "$out_dir" && sha256sum build-inputs.sha256 >build-inputs.digest) ||
    die "failed to checksum the checksum manifest"

  ok "build input checksum: out/build-inputs.sha256"
  ok "manifest digest: $(cut -d' ' -f1 "$out_dir/build-inputs.digest")"
}

verify_build_checksums() {
  (cd "$ROOT" && sha256sum --check --quiet "$OUT_DIR/build-inputs.sha256") ||
    die "build input checksum verification failed"
  ok "checksum manifest verifies"
}

checksum_image() {
  [ -f "$OUT_DIR/$IMAGE_NAME" ] ||
    die "image not found: out/$IMAGE_NAME"
  (cd "$OUT_DIR" && sha256sum "$IMAGE_NAME" >"$IMAGE_NAME.sha256") ||
    die "failed to checksum image"
  ok "image checksum: out/$IMAGE_NAME.sha256"
}

run_static_checks() {
  validate_config
  validate_required_files
  validate_shell
  scan_secrets
  write_build_checksums
  verify_build_checksums
}

require_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    die "run the build as an unprivileged user; pmbootstrap uses sudo/doas itself"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

check_qemu_binary() {
  local version
  if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
    die "qemu-system-aarch64 is required to boot the image"
  fi
  version=$(qemu-system-aarch64 --version | sed -n 's/^QEMU emulator version \([0-9][0-9.]*\).*/\1/p' | head -1)
  [ -n "$version" ] || die "could not determine qemu-system-aarch64 version"
  if [ "$(printf '%s\n%s\n' "$QEMU_MIN_VERSION" "$version" | sort -V | head -1)" != "$QEMU_MIN_VERSION" ]; then
    die "qemu-system-aarch64 $version is older than $QEMU_MIN_VERSION"
  fi
  ok "qemu-system-aarch64 $version"
}
