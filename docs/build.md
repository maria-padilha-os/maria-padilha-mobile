# Building the QEMU image

This repository builds a **QEMU-bootable aarch64 image first**. The physical
PinePhone target is documented but not built or flashed in this milestone.

## Layout

| Path | Purpose |
| --- | --- |
| `scripts/build.sh` | Build entry point; wraps the pinned toolchain |
| `scripts/run-qemu.sh` | Boot the built image with QEMU |
| `scripts/lib.sh` | Shared config, validation and checksum helpers |
| `config/build.conf` | Pinned release, toolchain commits and mirrors |
| `config/keyboard/keyboard.conf` | Squeekboard package, layouts, orientation and privacy policy |
| `config/power/power.conf` | Battery, charge-threshold, thermal and suspend policy |
| `config/modem/modem.conf` | ModemManager package, D-Bus interfaces and telephony privacy policy |
| `scripts/telephony-bridge.py` | ModemManager D-Bus to Quickshell telephony bridge |
| `config/power/systemd/` | Sleep/logind drop-ins and the charge-threshold oneshot |
| `config/power/udev/` | `power_supply` add rule for the threshold helper |
| `scripts/power-diagnostic.sh` | One-shot read-only battery/thermal/suspend report |
| `scripts/power-charge-thresholds.sh` | Hardware-gated 20–80% threshold helper |
| `scripts/stage-power-config.sh` | Stage the power tree; never touches the live system |
| `devices/<name>/device.conf` | Per-target device, UI and QEMU settings |
| `devices/qemu-aarch64/` | First-class virtual target |
| `devices/pine64-pinephone/` | Deferred physical reference; build refuses it |
| `shell/` | Touch-first Quickshell prototype; not installed by the image builder yet |
| `tests/build.sh` | Config/files/secrets/checksum gate (unprivileged) |
| `tests/keyboard.sh` | Keyboard config/layout/privacy and installer checks |
| `tests/power.sh` | Power config, sysfs fixtures, threshold no-op, suspend guard and staging |
| `tests/modem.sh` | ModemManager policy, real no-modem daemon and emulated call/SMS flow |
| `tests/shell.sh` | Palette, QML lint, self-test, telephony privacy and offscreen render checks |
| `tests/all.sh` | Repository checks used by CI |

## Prerequisites

- Linux host, `git`, Python 3, `sha256sum`, `find`/`xargs`
- For the telephony checks only: `ModemManager`, `mmcli`,
  `dbus-run-session` and Python Gio/GLib introspection. If they are missing the
  emulated and real-daemon checks are skipped explicitly; the static policy
  checks still run.
- `qemu-system-aarch64` **only** for `--boot` / `scripts/run-qemu.sh`
- `sudo` or `doas` **only** for a full `pmbootstrap` build. pmbootstrap uses
  chroot and mount internally; the wrapper never calls either directly.
- No root for the keyboard checks or `scripts/install-squeekboard.sh`; the
  installer writes only under the user's data directory and applies
  unprivileged gsettings.

The checks in this repository do not need root and do not touch a block
device. Run the full build on a dedicated builder or disposable VM that can
authorize pmbootstrap's privileged chroot/mount work.

## Quick start

```sh
make check                 # same as tests/build.sh; no network, no privileges
make build-dry-run         # print the pinned build plan
make build                 # full image build (builder with sudo/doas)
make boot                  # build, then boot with QEMU
make qemu                  # boot an already-built image
make test                  # repository CI checks, including keyboard, power and modem
make power-test            # power config, fixtures, threshold no-op, suspend guard
make modem-test            # ModemManager policy, no-modem daemon, emulated call/SMS flow
make power-diagnostic      # one-shot read-only battery/thermal/suspend report
make stage-power           # stage power drop-ins/helper under .scratch/power-root
```

Direct equivalents:

```sh
scripts/build.sh --check
scripts/build.sh --dry-run
scripts/build.sh
scripts/run-qemu.sh
```

The default target is `qemu-aarch64`. `scripts/build.sh --device NAME` selects
another `devices/NAME/device.conf`; physical targets are rejected.

## Pinned inputs

The critical path contains no floating branch or container tag:

| Input | Pin |
| --- | --- |
| Nura release line | `v26.06` stable (ADR 0001) |
| `pmbootstrap` | `2.3.1`, commit `9252400…` |
| `pmaports` | commit `817ed87…` |
| Device | `qemu-aarch64`, aarch64 |
| UI / init | Phosh / systemd |
| Mirrors | versioned HTTPS Alpine and postmarketOS mirrors |

`pmbootstrap` is fetched at the exact commit and its reported version is
checked before use. `pmaports` is fetched at the exact commit and its
`HEAD` is verified. Build files and config are checksummed into
`out/build-inputs.sha256`; the image gets `out/<image>.sha256`.

## What the build does

1. Validates config, required files, shell syntax, secrets and checksums.
2. Refuses to run as root or to build a physical target.
3. Fetches pinned `pmbootstrap` and `pmaports` into `.scratch/build/`.
4. Writes a pmbootstrap config for the device, Phosh and systemd, with the
   Squeekboard, UPower, lm-sensors and ModemManager packages in
   `extra_packages`.
5. Runs `pmbootstrap install --no-split` to create the QEMU image.
6. Exports the image to `out/maria-padilha-qemu-aarch64.img` and writes its
   SHA-256 checksum.

The full build does not install the power systemd/udev tree into the image by
itself. `scripts/stage-power-config.sh --dest <rootfs>` fills a staging tree
that the image packaging step can copy in; this keeps the unprivileged wrapper
from writing to host `/etc` or `/usr`. The battery, thermal and suspend policy
and its known limitations are in [`docs/power.md`](power.md). The manual QEMU
gate is [`docs/qemu-power-checklist.md`](qemu-power-checklist.md).

No partitioner, bootloader installer or flasher is implemented here; the
wrapper deliberately delegates image assembly to pmbootstrap. The `shell/`
prototype is a separate Quickshell application and is not installed into the
image by this builder yet. The on-screen keyboard package and layouts are
documented in [`docs/keyboard.md`](keyboard.md); the layout installer is a
user-session step, not a privileged image-build step.

## Booting in QEMU

```sh
scripts/run-qemu.sh
# interactive window:
PADILHA_QEMU_DISPLAY=gtk scripts/run-qemu.sh
```

The helper verifies the image checksum first, then runs the pinned
`pmbootstrap qemu` path with aarch64 emulation (`--no-kvm`) and no block
device. Headless is the default so CI needs no display server. The expected
result is a Phosh session at the device's configured resolution; a boot that
reaches the login/session is the milestone gate, not a performance benchmark.

## Re-pinning

1. Resolve the exact `v26.06` `pmaports` release commit.
2. Update `PMAPORTS_COMMIT` in `config/build.conf`.
3. Update `PMBOOTSTRAP_VERSION` / `PMBOOTSTRAP_COMMIT` together when moving
   pmbootstrap.
4. Run `make check`, then a full QEMU build and boot on a builder.
5. Record the change in the commit message; never replace a pin with a branch
   name or a floating tag.

## Out of scope

- flashing, partitioning or writing to physical devices
- a polling thermal/power daemon, a timer unit or a laptop suspend test
- bootloader unlock/bypass instructions
- claiming a real call, SMS, carrier registration or call-audio result without
  a supported device/module; see [`docs/modem.md`](modem.md)
- claiming PinePhone support before the physical checklist passes
- Android userspaces or Android compatibility layers
- publishing unsigned or unchecked images
