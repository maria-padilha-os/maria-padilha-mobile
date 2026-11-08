# Maria Padilha Mobile

**Maria Padilha de Bolso** — the touch-first Maria Padilha mobile OS.

This repository is the mobile image and shell. It shares the Padilha palette,
wallpaper language, and design tokens with the desktop, but it is not a desktop
session squeezed onto a phone.

## Status

**Base decided and image scaffold in place.** [ADR 0001](docs/adr/0001-mobile-base-and-reference-device.md)
selects postmarketOS (Nura) stable on Alpine with Phosh, `qemu-aarch64` as the
QEMU reference, and PinePhone-class close-to-mainline aarch64 handsets as the
first physical target. The scaffold implements that decision as a QEMU-first
image builder; Android is not the base and is not assumed.

| Area | Decision |
| --- | --- |
| Base | postmarketOS/Nura stable, Alpine |
| Interface | Phosh, with a Padilha palette layer |
| QEMU | `qemu-aarch64` |
| Physical | PinePhone-class close-to-mainline aarch64 |

No image has been built or flashed, and no device support is claimed until the
ADR's physical gate passes.

**Shell prototype in place.** [`shell/`](shell/) is a small Quickshell 0.3 /
Qt 6 touch shell with a status bar, app grid, notifications and a lock surface.
It reads the existing Maria Padilha colour state, adapts to portrait and
landscape, and can be rendered offscreen for screenshots. It is a prototype,
not the session image: it adds no device daemons, authentication backend or
flashing code. The full component notes are in [`shell/README.md`](shell/README.md).

## Touch-first shell prototype

The shell is a single fullscreen `xdg-shell` window. That choice keeps it
usable on a normal desktop compositor and in the QEMU guest under Phosh without
requiring `wlr-layer-shell`. It does not replace Phosh's own shell.

### Launch

Run from the checkout root in any Wayland session with Quickshell 0.3+ and the
Qt 6 QML runtime installed:

```sh
quickshell -p "$PWD/shell"
```

Useful prototype switches:

```sh
# deterministic demo apps, notifications, battery and network state
PADILHA_SHELL_DEMO=1 quickshell -p "$PWD/shell"

# windowed at a phone resolution instead of taking the whole screen
PADILHA_SHELL_SIZE=720x1280 quickshell -p "$PWD/shell"
PADILHA_SHELL_SIZE=1280x720 quickshell -p "$PWD/shell"

# open a specific surface and pre-fill the prototype lock PIN
PADILHA_SHELL_SURFACE=launcher quickshell -p "$PWD/shell"
PADILHA_SHELL_SURFACE=lock PADILHA_SHELL_PIN=1234 quickshell -p "$PWD/shell"

# override the colour state (the default is the live desktop state)
PADILHA_SCHEME="$HOME/.local/state/caelestia/scheme.json" quickshell -p "$PWD/shell"
```

The default palette path is `$XDG_STATE_HOME/caelestia/scheme.json`, falling
back to `~/.local/state/caelestia/scheme.json` and then to
[`shell/palettes/padilha-light.json`](shell/palettes/padilha-light.json), so the
same shell starts in a fresh QEMU guest with no desktop state. Generated
foreground roles are checked for contrast before use; an inconsistent scheme
cannot produce light text on a light surface.

The window can also be driven by `qs ipc call padilha-shell ...` while Quickshell
is running (`home`, `launcher`, `notifications`, `lock`, `unlock`,
`demoNotification`, `status`).

### QEMU

The shell is intended to run inside the guest's Wayland session as a normal
application:

1. Build and boot the checked `qemu-aarch64` image with the existing,
   unprivileged checks and the documented builder path
   ([`docs/build.md`](docs/build.md)); this task does not build, flash or
   partition anything.
2. Make Quickshell 0.3+ and the Qt 6 QML modules available in the guest.
3. Copy this checkout into the guest (or use a guest shared folder) and run
   `quickshell -p <checkout>/shell` from the guest Wayland session.

The fullscreen window sits under Phosh's own bar; that is expected for this
prototype. No daemon, image package or device support is added here, and the
QEMU boot gate remains a separate image task.

### Screenshot checklist

Screenshots must come from the shell only. Use the offscreen grab hook or a
dedicated nested compositor/workspace; never capture the whole desktop, private
windows or the agent terminal.

```sh
mkdir -p .scratch/screens
for size in 720x1280 1280x720; do
  for surface in home launcher notifications lock; do
    PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SIZE="$size" \
      PADILHA_SHELL_SURFACE="$surface" \
      PADILHA_SHELL_GRAB="$PWD/.scratch/screens/$surface-$size.png" \
      QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
      quickshell -p "$PWD/shell"
  done
done
```

| Check | 720x1280 portrait | 1280x720 landscape |
| --- | --- | --- |
| Status bar | clock, network, battery, notification badge readable | adds abbreviated date and network label |
| Navigation | bottom bar with Home / Apps / Alerts / Lock | left rail with the same four targets |
| Home | large clock, 3 quick actions, notification summary, four pinned columns | clock and quick actions side by side, six pinned columns |
| App grid | search field, four columns, no clipped labels | six columns, full-width search |
| Notifications | cards with app, summary, body and a 48 px dismiss target | same, capped at 820 px width |
| Lock | clock, privacy-safe count, 64 px keys, four PIN dots, any four digits unlock | clock left, 54 px keypad right |
| Palette | light and dark state readable, no light-on-light text | same |
| Touch | every actionable target is at least 48 px; keypad, nav and quick actions are larger | same |

Run `make test` (or `tests/shell.sh`) to check the palette fixtures, the
contrast guard, QML lint, the shell self-test and offscreen renders at both
resolutions. The visual test also verifies that each PNG has the expected
dimensions and is not a blank surface.

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
