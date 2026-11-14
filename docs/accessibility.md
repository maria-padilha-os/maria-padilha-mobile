# Mobile accessibility and dynamic-theme legibility

This note covers the touch-first shell in [`shell/`](../shell/). It records the
font-scaling, touch-target and contrast rules, the automated checks that enforce
them, the manual QEMU/Phosh checklist, and the small set of colour literals that
cannot follow a generated palette.

## Agreed thresholds

| Use | Minimum | Source |
| --- | --- | --- |
| Text (all sizes) | **4.5:1** | WCAG 2.2 AA normal text; applied to large text too for margin |
| Large text | 3:1 | WCAG 2.2 AA; the shell is stricter and uses 4.5:1 |
| Meaningful outline/focus indicator | **3:1** | WCAG 2.2 AA non-text contrast |
| Touch target | **48 x 48 logical px** | Padilha shell touch rule; WCAG 2.2 AA asks for at least 24 px |

The runtime tokens are `Theme.textContrastThreshold` (4.5),
`Theme.nonTextContrastThreshold` (3.0) and `Theme.minTouchTarget` (48).
`tests/shell/contrast_check.py` fails the build if a resolved text role is below
4.5:1 or a meaningful outline is below 3:1. The QML self-test walks the same
role list and fails the same way.

### Guarded roles

`Theme.qml` does not paint raw generated colours directly. Every foreground
role is resolved against the surfaces it can appear on:

1. the generated palette role is used if it reaches the threshold on **all** of
   those surfaces;
2. otherwise a soft warm neutral is used if it reaches the threshold;
3. otherwise pure black or white is chosen, which guarantees at least one of
   the two reaches 4.5:1 for any single background.

Multi-surface roles (for example text that can appear on `surface` and
`surfaceLow`) are resolved with `bestOnAll()`. This matters for a generated
scheme where `onSurface` is readable on the main surface but not on a container
surface.

The bundled light palette, the dark fixture and the intentionally broken light
fixture are checked on every run. The broken fixture proves that an inconsistent
generated scheme cannot produce light-on-light text: its raw text role is
1.03:1 and the guarded role is 18.15:1.

## Font scaling

The shell supports an explicit text scale so it works with an accessibility
setting without depending on a compositor-specific API:

```sh
PADILHA_SHELL_FONT_SCALE=1.5 quickshell -p "$PWD/shell"
```

- Default: `1.0`.
- Accepted range: `0.8` through `2.0` (the WCAG "resize text" target of 200%).
- Every `Text` and `TextInput` size is routed through `Theme.scaledFont()`.
  `tests/shell/accessibility_check.py` fails if a new raw `font.pixelSize`
  appears.
- Clock sizes, badge sizes, keyboard labels and button labels scale with the
  same token.
- The XML/QML viewport is unchanged; flexible `Flickable`/`ColumnLayout`
  surfaces scroll rather than assuming extra height.

The automated suite runs the shell self-test at `1.5` and renders the home
surface at `1.5`. It does not claim that every third-party or Phosh surface
follows the shell's scale: Squeekboard and Phosh have their own font/scale
settings.

## Minimum touch targets

Interactive controls opt in to `objectName: "padilha-touch-target"`. The QML
self-test walks the **visible** item tree and fails if a target is smaller than
`Theme.minTouchTarget`. `TouchButton`, `KeyboardKey`, `AppTile`, navigation,
notification summary/preview and the toast use the shared token directly.

| Control | Nominal size |
| --- | --- |
| Navigation item | 72 px (side rail 76 px high) |
| Quick action | 76-84 px |
| App tile | 64-86 px |
| Status-bar notification button | 48 px |
| Notification dismiss / clear | 48 px |
| Keyboard key | 48 px minimum, 54-82 px row height |
| Lock PIN / dial key | 54-64 px high |
| Send / back / refresh buttons | 48-52 px |
| Toast | 52 px high |

`PADILHA_SHELL_TOUCH_TARGET` can raise the minimum from 48 to 96 logical pixels;
values below 48 are refused. Decorative dots, badges and separators are not
interactive and are not treated as targets.

## Automated tests

```sh
make shell-test
# or individually
python3 tests/shell/palette_check.py       # fixtures + broken-palette guard
python3 tests/shell/contrast_check.py      # every resolved light/dark role pair
python3 tests/shell/accessibility_check.py # font/touch/colour/accessibility gates
tests/shell.sh                             # all of the above + QML self-tests/renders
```

The contrast test covers the roles used by the shell: `text`, `textMuted`,
`containerText`, `containerMuted`, `highText`, `highMuted`, `primaryText`,
`primaryContainerText`, `secondaryText`, `secondaryContainerText`,
`tertiaryContainerText`, `dangerText`, `dangerContainerText`, `successText`,
`successContainerText`, `inverseText` and `accent`, plus `danger`/`success` when
used as text. It also checks the meaningful `outline` on surface, container and
high container at 3:1.

## Manual accessibility checklist

Record **PASS**, **FAIL** or **N/A** and the exact build/commit for each row.
The automated gate is not a substitute for a real compositor and assistive
technology session. **No screen-reader or physical-keyboard session was run in
this checkout**; the rows below are the required manual gate for QEMU/Phosh or a
supported device.

### Prerequisites

1. Boot the QEMU reference image and start its Wayland/Phosh session.
2. Run the shell from this checkout:
   `PADILHA_SHELL_DEMO=1 quickshell -p "$PWD/shell"`.
3. For the dark pass, repeat with a dark scheme file, for example
   `PADILHA_SCHEME="$PWD/tests/shell/fixtures/padilha-dark.json"`.
4. For scaling, repeat with `PADILHA_SHELL_FONT_SCALE=1.5` and `2.0`.
5. Check whether a screen reader is available with `command -v orca`. Orca is
   not installed by this repository. If it is absent, mark the screen-reader
   rows **N/A (not installed)**; do not record them as passed.
6. Do not capture the whole desktop. Use the offscreen grab hook or a dedicated
   nested compositor as described in the repository README.

### Screen reader (where available)

| # | Check | Expected |
| --- | --- | --- |
| SR1 | Status bar | Clock, network and battery/AC are announced with their current value. |
| SR2 | Navigation | Home, Apps, Alerts and Lock have distinct names; the active/alerts state is understandable. |
| SR3 | App grid | Each tile announces the app name; activating it launches the app. |
| SR4 | Notifications | Summary/card body and app name are announced; Dismiss and Clear have names. |
| SR5 | Lock privacy | The lock surface exposes only the notification count, never a body, sender or phone number. |
| SR6 | Lock keypad | Digits, Backspace and Unlock are named; the four PIN dots are not read as text. |
| SR7 | Calls | Status card, number display, dial digits, Call, Answer and Hang up have names. |
| SR8 | Messages | Sender, message body, Reply, Delete and Send have names; focus does not read hidden compose text. |
| SR9 | Text fields | Search, To and message body expose the field role and typed text; the focused field stays visible above the keyboard. |
| SR10 | Focus order | Focus follows visual order, does not get trapped and returns to a sensible control after a surface closes. |
| SR11 | Privacy | Typed text, SMS content and the prototype PIN never appear in shell stdout/logs. |

If Orca is available, run it before starting the shell and repeat SR1-SR11 in
both light and dark palettes. If the compositor exposes its own screen reader,
record its name/version instead. This repository makes no AT-SPI or Orca
compatibility claim until the row is actually observed.

### Keyboard (where available)

| # | Check | Expected |
| --- | --- | --- |
| KB1 | Tab / Shift+Tab | Focus moves through status, navigation, app tiles, cards and actions in visual order. |
| KB2 | Focus ring | A 2 px palette accent ring is visible in both light and dark palettes. |
| KB3 | Activation | Space or Enter activates focused buttons, app tiles, notification summary and lock preview. |
| KB4 | Escape | Escape closes the launcher or notification/message surface and returns focus to a usable control. |
| KB5 | Text input | Typing, selection, Backspace, Return and Escape work in the search, To and message fields. |
| KB6 | Compositor keyboard | Squeekboard opens for the focused field; typing on a physical keyboard still works and the OSK does not steal focus. |
| KB7 | Inline fallback | `PADILHA_SHELL_OSK=inline PADILHA_SHELL_KEYBOARD=1` shows the fallback panel; keys commit to the focused field and the field is not covered. |
| KB8 | Orientation | Repeat KB1-KB7 in 720x1280 portrait and 1280x720 landscape. |

### Visual, scaling and touch

| # | Check | Expected |
| --- | --- | --- |
| V1 | Light palette | No light-on-light or low-contrast text on home, launcher, notifications, lock, calls or messages. |
| V2 | Dark palette | No dark-on-dark text on the same surfaces. |
| V3 | 150% text | Home, launcher, notifications, lock, calls, messages and keyboard labels remain readable and are not clipped by their cards. |
| V4 | 200% text | The clock, headings, badges and key labels remain readable; flexible surfaces scroll where needed. |
| V5 | Touch targets | Every actionable control is at least 48 x 48 px; the QML self-test reports `touch-targets-sized` as `ok`. |
| V6 | Focus/outline | Keyboard focus and input focus are visible against both palettes. |
| V7 | Disabled controls | Disabled actions remain distinguishable without relying on colour alone (for example the Call button before a number is entered). |

### Recording

Paste the completed table into the task/PR note with the commit, QEMU image,
Phosh/Quickshell versions, palette files and any screen-reader version used.
A FAIL must be fixed or explicitly accepted with a follow-up; it must not be
silently recorded as PASS.

## Hardcoded colours that cannot follow the dynamic palette

All normal component colours come from `Theme`. The following literals remain,
and the static accessibility test allows them only in the listed files:

| Location | Literal(s) | Why it cannot follow the dynamic palette |
| --- | --- | --- |
| `shell/components/Theme.qml`, guarded-role initial values (`text`, `textMuted`, `containerText`, ...) | `#201a18`, `#52443f`, `#ffffff`, `#3a0a04`, `#2c1511`, `#251a00`, `#904b3e`, `#410002`, `#0c1f13`, `#ffedea` | QML properties need a value before the asynchronous `FileView` palette load completes. These are light-safe placeholders; `_refreshGuarded()` replaces them as soon as data exists. They are never the long-term palette. |
| `shell/components/Theme.qml`, `_defaults` | The light Padilha role values | Last-resort semantic defaults when the state file is missing **and** `shell/palettes/padilha-light.json` cannot be loaded. With no palette source there is nothing dynamic to follow; the fallback keeps the shell usable. |
| `shell/components/Theme.qml`, `bestOn()`/`bestOnAll()` neutrals | `Qt.rgba(0.075, 0.06, 0.055, 1)`, `Qt.rgba(0.99, 0.97, 0.96, 1)`, pure black/white | These are the contrast safety net, deliberately outside the palette. If a generated `onSurface`/`onPrimary` role fails, a neutral must be chosen instead of the palette role; this is what prevents light-on-light text. Pure black/white is the mathematical floor. |
| `shell/components/Theme.qml`, `_raw()` unknown-role fallback | `#000000` | Programmer-error fallback for a role missing from both the palette and `_defaults`. It is not used by a well-formed generated scheme; it exists so a typo cannot make a property undefined. |
| `shell/components/Icon.qml` | `#201a18` default `color` | `Icon` is a dependency-free drawing primitive with no `Theme` dependency, so it can be reused outside the shell. Every shell usage passes `theme.text`, `theme.*Text`, `theme.accent` or another guarded role explicitly. Only an embedding that forgets to set `color` sees the literal. |
| `shell/components/TouchButton.qml` | `#201a18` default `foreground` | Same standalone-component case. Every shell `TouchButton` receives a guarded palette foreground (or relies on the active palette pair); the default only keeps an unthemed standalone use visible. |
| `shell/palettes/padilha-light.json`, `tests/shell/fixtures/*.json` | Palette role values | These are palette **inputs**, not component colours. They are exactly what the dynamic theme bridge consumes. |

`tests/shell/fixtures/broken-light.json` is intentionally unreadable; it is a
test fixture for the guard, not a production palette.

There are no hardcoded visual colours in the surfaces, cards, dialogs or
keyboard components. `tests/shell/accessibility_check.py` enforces that:
a new colour literal outside the three fallback files fails the test.

## Known limitations

- The shell follows the generated palette, but Phosh's own bars, dialogs and
  Squeekboard keep their own theme; this repository does not recolour them.
- The contrast guard can choose a neutral when a generated role is inconsistent,
  so a heavily broken palette may not look like the desktop palette even though
  its text stays readable.
- `outlineVariant` is decorative and is not required to meet 3:1. Meaningful
  focus rings use the guarded `accent`; inputs and cards use `outline`.
- Font scaling covers the shell's QML only. The compositor screen reader and
  Squeekboard font settings are separate.
- The automated touch-target check covers instantiated, visible controls in the
  current surface; the manual checklist covers all surfaces and both
  orientations.
- No real screen reader, physical keyboard or QEMU session result is claimed by
  this document until the manual rows are filled in.
