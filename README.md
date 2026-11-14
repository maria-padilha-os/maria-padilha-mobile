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
| Keyboard | Squeekboard, with Padilha terminal/URL/PIN layouts |
| Modem | ModemManager, with Padilha calls and SMS surfaces |
| QEMU | `qemu-aarch64` |
| Physical | PinePhone-class close-to-mainline aarch64 |

No image has been built or flashed, and no device support is claimed until the
ADR's physical gate passes.

**Shell prototype in place.** [`shell/`](shell/) is a small Quickshell 0.3 /
Qt 6 touch shell with a status bar, app grid, notifications, a lock surface and
an optional in-shell keyboard fallback. It reads the existing Maria Padilha
colour state, adapts to portrait and landscape, and can be rendered offscreen
for screenshots. It is a prototype, not the session image: it adds no device
daemons, authentication backend or flashing code. The full component notes are
in [`shell/README.md`](shell/README.md).

**On-screen keyboard decided.** [ADR 0002](docs/adr/0002-on-screen-keyboard.md)
selects Squeekboard over Maliit for the Phosh image. The image installs the
keyboard package, and the repository ships Padilha layouts for terminals, URL
bars, password fields and PINs. The integration notes are in
[`docs/keyboard.md`](docs/keyboard.md); the real-session gate is the
[manual QEMU checklist](docs/qemu-keyboard-checklist.md). No physical-device
claim is made.

**Cellular modem, calls and SMS stack in place.** ModemManager owns modem
probing, SIM state, voice-call objects and SMS objects. A small D-Bus bridge
feeds Padilha calls and SMS surfaces; no custom AT/QMI/MBIM stack is added.
The integration is documented in [`docs/modem.md`](docs/modem.md) and the
choice in [ADR 0003](docs/adr/0003-modem-and-telephony.md). The calls UI uses
the MM Voice interface and the SMS UI uses the MM Messaging interface. No
modem was available for a real call or SMS test: the automated gate uses a real
ModemManager daemon with no modem plus an emulated ModemManager D-Bus service.
Call audio, emergency calls and SIM unlock are not claimed.

**Power, battery, thermal and suspend policy in place.** UPower supplies
battery/charging state to Phosh and the shell. A hardware-gated helper applies
a 20–80% charge window only when the kernel exposes the standard
`charge_control_*_threshold` attributes; unsupported hardware is a documented
no-op. A read-only diagnostic reports battery, charger, threshold and thermal
state. The suspend policy allows suspend but disables hibernation, hybrid sleep
and suspend-then-hibernate, and leaves idle handling to Phosh. The policy,
known limitations and the manual QEMU gate are in
[`docs/power.md`](docs/power.md) and
[`docs/qemu-power-checklist.md`](docs/qemu-power-checklist.md). Suspend was not
tested on the reference laptop, and no physical-device support is claimed.

## Touch-first shell prototype

The shell is a single fullscreen `xdg-shell` window. That choice keeps it
usable on a normal desktop compositor and in the QEMU guest under Phosh without
requiring `wlr-layer-shell`. It does not replace Phosh's own shell. Calls and
Messages are Padilha surfaces backed by ModemManager; they are not a second
telephony daemon.

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

# scale text (0.8-2.0) and raise the minimum touch target (48-96 px)
PADILHA_SHELL_FONT_SCALE=1.5 PADILHA_SHELL_TOUCH_TARGET=56 \
  quickshell -p "$PWD/shell"

# force the small in-shell fallback keyboard for a screenshot or demo
PADILHA_SHELL_OSK=inline PADILHA_SHELL_KEYBOARD=1 \
  PADILHA_SHELL_KEYBOARD_PURPOSE=terminal quickshell -p "$PWD/shell"
```

The default palette path is `$XDG_STATE_HOME/caelestia/scheme.json`, falling
back to `~/.local/state/caelestia/scheme.json` and then to
[`shell/palettes/padilha-light.json`](shell/palettes/padilha-light.json), so the
same shell starts in a fresh QEMU guest with no desktop state. Generated
foreground roles are checked for contrast before use; an inconsistent scheme
cannot produce light text on a light surface. The font-scale, touch-target,
contrast and manual screen-reader/keyboard requirements are in
[`docs/accessibility.md`](docs/accessibility.md).

The window can also be driven by `qs ipc call padilha-shell ...` while Quickshell
is running (`home`, `launcher`, `notifications`, `calls`, `messages`, `lock`,
`unlock`, `demoNotification`, `status`).

### On-screen keyboard

Squeekboard is the system keyboard in the Phosh guest. It is selected by
[ADR 0002](docs/adr/0002-on-screen-keyboard.md) because it is the Phosh-native
input method, consumes `text-input-v3` purpose/hints, and has declarative
layouts for terminal, URL and numeric fields. The shell does not reimplement a
system input method: it requests show/hide through Qt's input method and
reserves space from `InputMethod.keyboardRectangle`, so the focused field is
not covered. See [`docs/keyboard.md`](docs/keyboard.md) for the protocol path,
layout semantics and privacy contract.

The Padilha layouts are installed into the guest user's data directory with an
unprivileged script:

```sh
scripts/install-squeekboard.sh --apply-settings
```

The optional `KeyboardPanel.qml` fallback is only for the shell's own fields
and for offscreen/desktop development:

```sh
# default: let the compositor (Squeekboard) own the keyboard
PADILHA_SHELL_OSK=compositor quickshell -p "$PWD/shell"

# force the fallback; purpose is text, terminal, url or password
PADILHA_SHELL_OSK=inline PADILHA_SHELL_KEYBOARD=1 \
  PADILHA_SHELL_KEYBOARD_PURPOSE=url quickshell -p "$PWD/shell"
```

### QEMU

The shell is intended to run inside the guest's Wayland session as a normal
application:

1. Build and boot the checked `qemu-aarch64` image with the existing,
   unprivileged checks and the documented builder path
   ([`docs/build.md`](docs/build.md)); this task does not build, flash or
   partition anything.
2. Make Quickshell 0.3+ and the Qt 6 QML modules available in the guest, and
   confirm the image's `squeekboard` package is present.
3. Copy this checkout into the guest (or use a guest shared folder), install
   the layouts with `scripts/install-squeekboard.sh --apply-settings`, and run
   `quickshell -p <checkout>/shell` from the guest Wayland session.
4. Run the [manual QEMU keyboard checklist](docs/qemu-keyboard-checklist.md)
   for text-input, show/hide, terminal/URL/password layouts, both orientations
   and keyboard avoidance.

The fullscreen window sits under Phosh's own bar; that is expected for this
prototype. No daemon or device support is added here, and the QEMU boot gate
remains a separate image task. The keyboard package is pinned in
[`config/keyboard/keyboard.conf`](config/keyboard/keyboard.conf); no physical
device is used or claimed.

### Screenshot checklist

Screenshots must come from the shell only. Use the offscreen grab hook or a
dedicated nested compositor/workspace; never capture the whole desktop, private
windows or the agent terminal.

```sh
mkdir -p .scratch/screens
for size in 720x1280 1280x720; do
  for surface in home launcher notifications lock calls messages; do
    PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SIZE="$size" \
      PADILHA_SHELL_SURFACE="$surface" \
      PADILHA_SHELL_GRAB="$PWD/.scratch/screens/$surface-$size.png" \
      QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
      quickshell -p "$PWD/shell"
  done
  for purpose in text terminal url password; do
    PADILHA_SHELL_DEMO=1 PADILHA_SHELL_SIZE="$size" \
      PADILHA_SHELL_SURFACE=launcher PADILHA_SHELL_OSK=inline \
      PADILHA_SHELL_KEYBOARD=1 PADILHA_SHELL_KEYBOARD_PURPOSE="$purpose" \
      PADILHA_SHELL_GRAB="$PWD/.scratch/screens/keyboard-$purpose-$size.png" \
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
| Calls | status card, number display, 62 px dial pad, incoming/active call actions | status card, number display and dial pad within a 620 px column |
| Messages | status card, message cards, reply/delete and compose panel above the nav bar | same, capped at 760 px width |
| Keyboard | fallback panel ends above the focused search field; terminal, URL and password layouts are selectable | wide keys, shorter panel, focused field still visible |
| Palette | light and dark state readable, no light-on-light text | same |
| Touch | every actionable target is at least 48 px; keypad, nav, keys and quick actions are larger | same |
| Accessibility | 150% text stays readable; focus ring and touch targets remain visible | same |

Run `make test` to check the keyboard config/layouts/privacy policy, the
palette fixtures, the guarded contrast of every generated light/dark role, QML
lint, scalable-font/touch-target/accessible-name checks, the shell self-test
and offscreen renders at both resolutions. The visual test also verifies that
each PNG has the expected dimensions and is not a blank surface. The real
Squeekboard, screen-reader and physical-keyboard sessions are verified
separately with the [manual accessibility checklist](docs/accessibility.md) and
the [manual QEMU keyboard checklist](docs/qemu-keyboard-checklist.md).

## Power, battery and thermal

The image adds `upower` and `lm-sensors` to its package set. The shell treats a
present phone battery as the display battery instead of relying on UPower's
laptop flag, shows charging/low/critical state and remaining time when UPower
provides it, and falls back to `AC` when no battery exists (as in QEMU).

The charge-threshold helper is a single scan, not a daemon:

```sh
# read-only plan; this is the only mode the tests use
scripts/power-charge-thresholds.sh --dry-run

# one-shot systemd/udev/resume integration is staged, not installed live
scripts/stage-power-config.sh --dest .scratch/power-root
```

The service is `Type=oneshot`, the udev rule only handles `add`, and the sleep
hook only runs after resume. There is no timer and no polling loop. See
[`docs/power.md`](docs/power.md) for the full policy, the staging boundary and
the known limitations.

The read-only diagnostic works in the checkout, in the guest and on a supported
device:

```sh
scripts/power-diagnostic.sh          # human-readable, one scan
scripts/power-diagnostic.sh --json   # machine-readable
scripts/power-diagnostic.sh --strict # exit 1 if warnings are present
make power-test                      # fixture, no-op, guard and staging checks
```

The suspend-target guard refuses laptops and desktops; use QEMU or a supported
device and follow the [manual QEMU power checklist](docs/qemu-power-checklist.md).
The repository never suspends the reference laptop.

## Cellular modem, calls and SMS

ModemManager is the maintained modem stack. The image installs the
`modemmanager` package; the shell starts a small D-Bus adapter,
[`scripts/telephony-bridge.py`](scripts/telephony-bridge.py), and renders calls
and SMS in the Padilha surfaces. The bridge is not a modem daemon: it projects
ModemManager's MM Voice and MM Messaging objects into JSON and forwards dial,
answer, hangup, send and delete actions.

```sh
make modem-test     # policy, real no-modem ModemManager, emulated call/SMS flow
make shell-test     # calls/messages renders, QML lint and the privacy selftest
```

The shell is reachable with:

```sh
qs ipc call padilha-shell calls
qs ipc call padilha-shell messages
```

No-modem, ModemManager-unavailable, locked-SIM and capability-limited states
are rendered with disabled actions instead of being treated as fatal errors.
Message text and phone numbers are not written to logs or a local cache; the
in-memory list is repopulated from ModemManager. See
[`docs/modem.md`](docs/modem.md) for the interface map, privacy contract and
limitations, and [ADR 0003](docs/adr/0003-modem-and-telephony.md) for the stack
comparison.

**No real call or SMS was tested in this checkout.** The automated gate starts
a real ModemManager daemon on a private session bus with no modem, then uses an
emulated ModemManager D-Bus service for call/SMS state. It proves the bridge and
UI, not radio, carrier, audio or hardware. Call audio, emergency calls and SIM
PIN/PUK are explicitly not claimed. The manual supported-device path is
[`docs/qemu-telephony-checklist.md`](docs/qemu-telephony-checklist.md), and it
must never be recorded as passed without a real modem result.

## Goals

- touch-first status bar, launcher, app grid, notifications, and lock surface
- large touch targets and readable type in light and dark palettes
- Squeekboard on-screen keyboard with terminal, URL and password layouts
- ModemManager-backed calls and SMS with graceful no-modem states
- gesture navigation and safe power management
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
make accessibility-test # palette, contrast, font/touch and checklist gates
make keyboard-test # Squeekboard config/layout/privacy checks only
make power-test    # power config, diagnostic fixtures, threshold no-op, suspend guard
make modem-test    # ModemManager policy, no-modem daemon and emulated call/SMS flow
make power-diagnostic # one-shot read-only battery/thermal/suspend report
make stage-power   # stage systemd/udev/helper files under .scratch/power-root
```

Pinned `pmbootstrap`/`pmaports` inputs live in
[`config/build.conf`](config/build.conf), the Squeekboard package/layout policy
lives in [`config/keyboard/keyboard.conf`](config/keyboard/keyboard.conf), the
battery/thermal/suspend policy lives in
[`config/power/power.conf`](config/power/power.conf), the modem/telephony policy
lives in [`config/modem/modem.conf`](config/modem/modem.conf), and the QEMU
target lives in [`devices/qemu-aarch64/`](devices/qemu-aarch64/). Flashing and
physical partitioning are out of scope; only the QEMU target is built in this
milestone.
