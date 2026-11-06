# Maria Padilha Mobile

**Maria Padilha de Bolso** — the touch-first Maria Padilha mobile OS.

This repository is the mobile image and shell. It shares the Padilha palette,
wallpaper language, and design tokens with the desktop, but it is not a desktop
session squeezed onto a phone.

## Status

**Base decided (2026-11-06).** [ADR 0001](docs/adr/0001-mobile-base-and-reference-device.md)
selects postmarketOS (now Nura) with Phosh, `qemu-aarch64` as the QEMU
reference, and PinePhone-class close-to-mainline aarch64 handsets as the first
physical target.

| Area | Decision |
| --- | --- |
| Base | postmarketOS/Nura stable, Alpine |
| Interface | Phosh, with a Padilha palette layer |
| QEMU | `qemu-aarch64` |
| Physical | PinePhone-class close-to-mainline aarch64 |

No image has been built or flashed, and no device support is claimed until the
ADR's physical gate passes. Do not assume Android.

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

## Development

Only the README, the ADR, and the test scaffold exist. `tests/all.sh` checks
basic hygiene and the ADR contract; it does not build or flash anything.
