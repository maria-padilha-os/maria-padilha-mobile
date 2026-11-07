# Maria Padilha Mobile

**Maria Padilha de Bolso** — the touch-first Maria Padilha mobile OS.

This repository is the mobile image and shell. It shares the Padilha palette,
wallpaper language, and design tokens with the desktop, but it is not a desktop
session squeezed onto a phone.

## Status

**Image scaffold.** ADR 0001 selects postmarketOS/Nura on the stable channel
with Phosh and `qemu-aarch64` as the first reference. The ADR is not merged on
this branch yet, so [`docs/base-assumption.md`](docs/base-assumption.md)
records the assumed base instead of silently choosing another one.

The first milestone is a QEMU-bootable aarch64 image. No phone is required,
and this repository does not flash, partition or claim support for physical
devices. Android is not the base and is not assumed.

## Goals

- touch-first status bar, launcher, app grid, notifications, and lock surface
- large touch targets and readable type in light and dark palettes
- on-screen keyboard, gesture navigation, and safe power management
- a QEMU-bootable image before any physical-device work
- explicit device support and recovery documentation

## Relationship to the desktop

The desktop shell and theme engine live in
[`maria-padilha-de`](https://github.com/maria-padilha-os/maria-padilha-de);
tracked configs live in
[`maria-padilha-dotfiles`](https://github.com/maria-padilha-os/maria-padilha-dotfiles).
The desktop image is
[`maria-padilha-os`](https://github.com/maria-padilha-os/maria-padilha-os).

## Building

The build entry point is [`scripts/build.sh`](scripts/build.sh); see
[`docs/build.md`](docs/build.md) for prerequisites and the full flow.

```sh
make check        # unprivileged config/files/secrets/checksum gate
make build        # full QEMU image build on a builder with sudo/doas
make qemu         # boot the checked image with QEMU
make test         # CI checks
```

Pinned `pmbootstrap`/`pmaports` inputs live in
[`config/build.conf`](config/build.conf), and the QEMU target lives in
[`devices/qemu-aarch64/`](devices/qemu-aarch64/). Flashing and physical
partitioning are out of scope; only the QEMU target is built in this
milestone.
