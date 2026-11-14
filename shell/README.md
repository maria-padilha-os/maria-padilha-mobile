# Maria Padilha Mobile shell prototype

A small touch-first Quickshell shell for the Maria Padilha mobile work. It is a
prototype: it does not replace Phosh, does not authenticate users, does not
implement device daemons and does not flash anything. It reads UPower and
NetworkManager status and talks to ModemManager through the small telephony
bridge for calls and SMS.

The launch instructions and the required screenshot checklist live in the
[repository README](../README.md#touch-first-shell-prototype). This file maps
the implementation and records the scope.

## Surfaces

| Surface | File | What it does |
| --- | --- | --- |
| Status bar | `components/StatusBar.qml` | clock, network, UPower battery/charging state, low-battery colour and notification badge |
| Home | `surfaces/HomeSurface.qml` | large clock, quick actions, notification summary, pinned apps |
| Launcher | `surfaces/LauncherSurface.qml` | searchable app grid, real `DesktopEntry` launch in normal mode |
| Notifications | `surfaces/NotificationsSurface.qml` | live `NotificationServer` list, demo cards, dismiss and clear |
| Calls | `surfaces/CallsSurface.qml`, `components/CallCard.qml`, `components/DialPad.qml` | ModemManager Voice calls, dial/incoming/active states, graceful no-modem states |
| Messages | `surfaces/MessagesSurface.qml`, `components/SmsCard.qml` | ModemManager Messaging list, reply/send/delete, in-memory only |
| Settings | `surfaces/SettingsSurface.qml`, `settings/` | Network, Display, Sound, Battery, Language and About pages with touch rows |
| Lock | `surfaces/LockSurface.qml` | clock, privacy-safe notification count, PIN dots, large keypad |
| Navigation | `components/NavBar.qml`, `components/SideRail.qml` | bottom bar in portrait, side rail in landscape |
| Keyboard fallback | `components/KeyboardPanel.qml`, `components/KeyboardKey.qml`, `components/KeyboardLayouts.qml` | optional in-shell panel for the shell's own text fields |

The shell is one fullscreen `FloatingWindow` (an `xdg-shell` surface), not a
layer-shell panel. That is deliberate: it runs on a normal desktop compositor
and on Phosh in the QEMU guest without requiring a wlr-layer-shell extension.
The trade-off is that Phosh's own top bar remains above it and the shell cannot
reserve a work area for other applications.

## Power status

`components/DeviceStatus.qml` reads `UPower.displayDevice` and treats any ready,
present `UPowerDeviceType.Battery` as the display battery. It deliberately does
not depend on UPower's `isLaptopBattery`, which is false on phones. The status
bar shows percentage, charging, low/critical colour and, in landscape, time to
empty or full when UPower provides it. With no battery (the usual QEMU case)
the label falls back to `AC` and a power icon.

The shell is read-only with respect to power: it never writes a charge
threshold and never suspends the machine. The image-level policy, diagnostics
and QEMU suspend gate are in [`docs/power.md`](../docs/power.md) and
[`docs/qemu-power-checklist.md`](../docs/qemu-power-checklist.md).

## Cellular modem and telephony

`components/TelephonyService.qml` owns one small bridge process
(`scripts/telephony-bridge.py`) and projects ModemManager's Voice/Messaging
D-Bus objects into QML. The shell does not implement a modem protocol, own a
second daemon or persist messages. `CallsSurface.qml` and
`MessagesSurface.qml` render `no-modem`, `unavailable`, `locked`, `searching`
and capability-limited states with the shared `TelephonyStatusCard.qml`.
In demo mode the same surfaces use deterministic in-memory data and do not
start the bridge.

Call audio, emergency calls and SIM PIN/PUK are out of scope; the calls UI
creates, answers and hangs up ModemManager call objects, but does not claim a
working audio path. The full policy is in
[`docs/modem.md`](../docs/modem.md) and
[ADR 0003](../docs/adr/0003-modem-and-telephony.md).

## Palette wiring

`components/Theme.qml` reads the existing Maria Padilha colour state from:

1. `PADILHA_SCHEME`, when set;
2. `$XDG_STATE_HOME/caelestia/scheme.json`;
3. `~/.local/state/caelestia/scheme.json`;
4. `shell/palettes/padilha-light.json` as the bundled fallback.

The file is watched for atomic rewrites, so changing the desktop palette
updates the shell without a restart. Both `mode: "light"` and `mode: "dark"`
are supported.

Every foreground is passed through `bestOn()` with a WCAG contrast target. If
the generated scheme has, for example, a near-white `onSurface` on a near-white
`surface`, the shell chooses a high-contrast neutral instead of painting light
text on a light surface. `tests/shell/fixtures/broken-light.json` exercises that
path and `tests/shell/palette_check.py` mirrors the guard outside QML.

All icons are drawn by `components/Icon.qml` with Qt Canvas. There is no icon
font dependency, which keeps the shell usable in a minimal QEMU guest.

## Settings

`surfaces/SettingsSurface.qml` hosts the touch settings pages. Portrait shows
six large category cards or one full-width page; landscape adds a persistent
category rail. The page rows are mobile ports of the desktop Nexus common rows
(`PageBase`, `SectionHeader`, `ToggleRow`, `SliderRow`, `SelectRow`, `InfoRow`,
`RowButton`, `StepperRow`) and keep the same grouped-card interaction language
without importing the desktop `Caelestia.Config` plugin.

`components/SettingsStore.qml` validates every value and persists preferences
to the existing `$PADILHA_CONFIG_DIR/shell.json` (normally
`~/.config/padilha/shell.json`). It uses `appearance.font.scale`,
`general.language`, `services.clockFormat`, `general.battery.criticalLevel` and
`utilities.toasts.chargingChanged`. Writes are atomic and preserve unknown
keys. Brightness, audio volume/mute and Wi-Fi stay with the backlight subsystem,
PipeWire/WirePlumber and NetworkManager; charge thresholds stay with the image
helper. See [`docs/settings.md`](../docs/settings.md).

The interface scale is applied to the shell surface itself, so changing it
rescales the status bar, navigation and pages rather than only a preview. Only
upscaling (100%, 110%, 120%) is offered so the 48 px touch floor is never
reduced. Demo mode uses deterministic network, battery and about-page data and
never writes to a device or radio; the self-test asserts the NetworkManager
write counter did not change.

## Responsive rules

- 720x1280 portrait: bottom navigation, four-column app grid, stacked clock and
  quick actions, 64 px keypad, full-width notification cards.
- 1280x720 landscape: 96 px side rail, six-column app grid, clock and quick
  actions side by side, 54 px keypad in a two-column lock layout, notification
  cards capped at 820 px.
- Actionable controls are at least 48 px; navigation is 72 px, quick actions are
  76-84 px, app tiles are 68-86 px and settings rows are 60-78 px.
- `PADILHA_SHELL_SIZE=WxH` forces a windowed size for testing.
- The shell body gets a bottom inset from `KeyboardPanel.qml` in inline mode,
  or from `InputMethod.keyboardRectangle` when Squeekboard is open, so the
  focused field and cursor remain visible above the keyboard in both
  orientations.

## Keyboard and text input

Squeekboard is the primary keyboard for the Phosh image; the decision and
integration notes are in [`docs/adr/0002-on-screen-keyboard.md`](../docs/adr/0002-on-screen-keyboard.md)
and [`docs/keyboard.md`](../docs/keyboard.md). The shell registers a focused
`TextInput` with `ShellState.attachKeyboard()` and asks Qt's input method to
show/hide; it does not implement a system input method.

`KeyboardPanel.qml` is an opt-in fallback for the shell's own fields and for
offscreen/desktop development. It commits text directly to the focused
`TextInput`, never takes focus itself, and does not write or log that text. The
fallback layout is chosen per purpose (`text`, `terminal`, `url`, `password`)
and uses a shorter key row in landscape.

## Prototype controls

- Tap a pinned app or launcher tile to launch it. In demo mode the apps are a
  fixed catalogue and only show a toast.
- Tap the bell in the status bar, the summary card or the Alerts nav item to open
  the notification centre. Dismiss with the 48 px close button or clear all.
- Open Calls or Messages from the pinned apps, the launcher, or
  `qs ipc call padilha-shell calls|messages`. The dial pad and compose fields
  are disabled when ModemManager reports no usable voice or SMS capability.
- Incoming calls and SMS add a notification and a toast. The lock surface still
  shows only the count, never a message body or number.
- Tap Lock in the quick actions or navigation. Any four digits unlock; the PIN
  is a UI stub, not authentication.
- Focus toggles a local do-not-disturb flag and never touches system settings.
- Tap the launcher search field to focus it. In compositor mode Squeekboard
  opens; with `PADILHA_SHELL_OSK=inline` the fallback panel opens. Tap the
  down-arrow key or outside the field to hide it.
- Open Settings from the launcher, the pinned grid, the Network quick action or
  `qs ipc call padilha-shell settings`. Use the category cards/rail or
  `settingsPage <page>` to switch pages; the back target returns to the
  overview or Home.
- `qs ipc call padilha-shell <home|launcher|notifications|calls|messages|settings|lock|unlock|demoNotification|status>`
  drives the running shell.

## Test hooks

These variables exist for reproducible screenshots and tests:

| Variable | Effect |
| --- | --- |
| `PADILHA_SCHEME` | palette state file to read |
| `PADILHA_SHELL_DEMO=1` | deterministic demo apps, notifications, 82% battery, Wi-Fi, network list and about data |
| `PADILHA_SHELL_SIZE=WxH` | force the window size |
| `PADILHA_SHELL_SURFACE=home\|launcher\|notifications\|calls\|messages\|settings\|lock` | initial surface |
| `PADILHA_SHELL_SETTINGS_PAGE=index\|network\|display\|sound\|battery\|language\|about` | initial settings page |
| `PADILHA_CONFIG_DIR` | existing Padilha config directory |
| `PADILHA_SETTINGS_CONFIG` | explicit `shell.json` path for persistence tests |
| `PADILHA_SETTINGS_WRITE=1` | allow writes in demo mode |
| `PADILHA_SETTINGS_SELFTEST=1` | run settings validation, navigation and temp-config persistence checks |
| `PADILHA_SETTINGS_CAPTURE=1` | call `padilha-config capture` after a save |
| `PADILHA_SHELL_QUERY` | pre-fill the launcher search |
| `PADILHA_SHELL_PIN` | pre-fill the prototype PIN dots |
| `PADILHA_SHELL_GRAB=/path.png` | render the shell to a PNG and exit |
| `PADILHA_SHELL_GRAB_DELAY` | grab delay in ms (default 1200) |
| `PADILHA_SHELL_SELFTEST=1` | run palette/state assertions and exit |
| `PADILHA_SHELL_OSK=compositor\|inline\|auto\|off` | keyboard backend: Squeekboard/compositor (default), forced fallback, auto fallback, or no shell keyboard |
| `PADILHA_SHELL_KEYBOARD=1` | force the fallback panel on, for screenshots/tests |
| `PADILHA_SHELL_KEYBOARD_PURPOSE=text\|terminal\|url\|password` | initial fallback layout purpose |
| `PADILHA_SHELL_KEYBOARD_VIEW=base\|upper\|numbers\|symbols` | initial fallback view |
| `PADILHA_SHELL_KEYBOARD_INSET=0.0-0.60` | override the conservative compositor keyboard reserve |
| `PADILHA_TELEPHONY_DEMO=1\|0` | force deterministic in-memory telephony state, or force the real bridge |
| `PADILHA_TELEPHONY_BACKEND=auto\|off` | start the bridge, or render the no-modem state without a process |
| `PADILHA_TELEPHONY_BUS=session` | use the session bus for tests/emulation |
| `PADILHA_TELEPHONY_MESSAGE=...` | add an in-memory demo message for the no-logging check |

## Verification

```sh
make test            # repository checks, including keyboard, modem, settings and shell tests
tests/keyboard.sh    # Squeekboard config/layouts/privacy and installer checks
tests/modem.sh       # ModemManager policy, no-modem daemon, emulated call/SMS flow
tests/settings.sh    # settings policy, navigation/validation/persistence and page renders
tests/shell.sh       # palette, contrast, qmllint, self-test, telephony renders
```

The offscreen render path sets `QT_QPA_PLATFORM=offscreen` and
`QSG_RHI_BACKEND=software`. It captures only the shell's own item tree, so no
private window or terminal is part of a screenshot. On a machine without
Quickshell the visual part of `tests/shell.sh` and `tests/settings.sh` is
skipped; the palette and static checks still run.

## Out of scope

- system power daemons, suspend/resume control or charge-threshold writes (the
  shell only reads UPower status)
- call audio routing, emergency calling, SIM unlock, MMS, USSD, contacts or
  call history (the telephony surfaces only project ModemManager state)
- PAM, fingerprint or any real lock authentication
- a system-wide input method implementation (Squeekboard and Phosh provide it;
  the QML fallback only types into the shell's own fields)
- image packaging, flashing, partitioning or physical-device support claims
