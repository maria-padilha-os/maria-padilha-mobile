# Maria Padilha Mobile

**Maria Padilha de Bolso** — the touch-first Maria Padilha mobile OS.

This repository is the mobile image and shell. It shares the Padilha palette,
wallpaper language, and design tokens with the desktop, but it is not a desktop
session squeezed onto a phone.

## Status

**Scaffold / base decision.** The mobile base and reference device are not
decided. The first queued task is an ADR comparing Arch Linux ARM with
Phosh/Plasma Mobile against postmarketOS, including kernel/firmware support,
maintenance cost, and how much of the Padilha shell can be reused.

Do not assume Android, and do not flash a device yet.

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

Only the README and test scaffold exist. `tests/all.sh` checks basic hygiene; it
does not build or flash anything.
