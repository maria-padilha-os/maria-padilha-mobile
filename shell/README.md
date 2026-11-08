# Maria Padilha Mobile shell prototype

A small touch-first Quickshell shell for the Maria Padilha mobile work. It is a
prototype: it does not replace Phosh, does not authenticate users, does not
talk to device daemons and does not flash anything.

The launch instructions and the required screenshot checklist live in the
[repository README](../README.md#touch-first-shell-prototype). This file maps
the implementation and records the scope.

## Surfaces

| Surface | File | What it does |
| --- | --- | --- |
| Status bar | `components/StatusBar.qml` | clock, network, battery, charging state and notification badge |
| Home | `surfaces/HomeSurface.qml` | large clock, quick actions, notification summary, pinned apps |
| Launcher | `surfaces/LauncherSurface.qml` | searchable app grid, real `DesktopEntry` launch in normal mode |
| Notifications | `surfaces/NotificationsSurface.qml` | live `NotificationServer` list, demo cards, dismiss and clear |
| Lock | `surfaces/LockSurface.qml` | clock, privacy-safe notification count, PIN dots, large keypad |
| Navigation | `components/NavBar.qml`, `components/SideRail.qml` | bottom bar in portrait, side rail in landscape |

The shell is one fullscreen `FloatingWindow` (an `xdg-shell` surface), not a
layer-shell panel. That is deliberate: it runs on a normal desktop compositor
and on Phosh in the QEMU guest without requiring a wlr-layer-shell extension.
The trade-off is that Phosh's own top bar remains above it and the shell cannot
reserve a work area for other applications.

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

## Responsive rules

- 720x1280 portrait: bottom navigation, four-column app grid, stacked clock and
  quick actions, 64 px keypad, full-width notification cards.
- 1280x720 landscape: 96 px side rail, six-column app grid, clock and quick
  actions side by side, 54 px keypad in a two-column lock layout, notification
  cards capped at 820 px.
- Actionable controls are at least 48 px; navigation is 72 px, quick actions are
  76-84 px and app tiles are 68-86 px.
- `PADILHA_SHELL_SIZE=WxH` forces a windowed size for testing.

## Prototype controls

- Tap a pinned app or launcher tile to launch it. In demo mode the apps are a
  fixed catalogue and only show a toast.
- Tap the bell in the status bar, the summary card or the Alerts nav item to open
  the notification centre. Dismiss with the 48 px close button or clear all.
- Tap Lock in the quick actions or navigation. Any four digits unlock; the PIN
  is a UI stub, not authentication.
- Focus toggles a local do-not-disturb flag and never touches system settings.
- `qs ipc call padilha-shell <home|launcher|notifications|lock|unlock|demoNotification|status>`
  drives the running shell.

## Test hooks

These variables exist for reproducible screenshots and tests:

| Variable | Effect |
| --- | --- |
| `PADILHA_SCHEME` | palette state file to read |
| `PADILHA_SHELL_DEMO=1` | deterministic demo apps, notifications, 82% battery, Wi-Fi |
| `PADILHA_SHELL_SIZE=WxH` | force the window size |
| `PADILHA_SHELL_SURFACE=home\|launcher\|notifications\|lock` | initial surface |
| `PADILHA_SHELL_QUERY` | pre-fill the launcher search |
| `PADILHA_SHELL_PIN` | pre-fill the prototype PIN dots |
| `PADILHA_SHELL_GRAB=/path.png` | render the shell to a PNG and exit |
| `PADILHA_SHELL_GRAB_DELAY` | grab delay in ms (default 1200) |
| `PADILHA_SHELL_SELFTEST=1` | run palette/state assertions and exit |

## Verification

```sh
make test            # repository checks, including tests/shell.sh
tests/shell.sh       # palette, contrast, qmllint, self-test, offscreen renders
```

The offscreen render path sets `QT_QPA_PLATFORM=offscreen` and
`QSG_RHI_BACKEND=software`. It captures only the shell's own item tree, so no
private window or terminal is part of a screenshot. On a machine without
Quickshell the visual part of `tests/shell.sh` is skipped; the palette checks
still run.

## Out of scope

- device daemons, telephony, modem, suspend or power management integration
- PAM, fingerprint or any real lock authentication
- an on-screen keyboard implementation (the compositor/Phosh provides one; the
  launcher search field requests focus normally)
- image packaging, flashing, partitioning or physical-device support claims
