# On-screen keyboard and text input

Maria Padilha Mobile uses **Squeekboard** as the primary on-screen keyboard.
The choice and the comparison with Maliit are in
[ADR 0002](adr/0002-on-screen-keyboard.md). This document describes how the
keyboard is wired, how the shell avoids covering a focused field, and what is
verified where.

## Components

| Component | Path | Role |
| --- | --- | --- |
| Keyboard policy | `config/keyboard/keyboard.conf` | backend, package, layout names, orientation and privacy flags |
| Squeekboard layouts | `config/keyboard/layouts/` | default/wide, terminal, URL and PIN data |
| Installer | `scripts/install-squeekboard.sh` | copies layouts to the user data directory; optional unprivileged gsettings |
| Shell fallback panel | `shell/components/KeyboardPanel.qml`, `KeyboardKey.qml`, `KeyboardLayouts.qml` | in-process fallback for development and compositors without an OSK |
| Shell keyboard state | `shell/components/ShellState.qml` | focus registration, show/hide, text commit, layout/orientation state |
| Shell layout | `shell/shell.qml` | bottom inset, panel placement, external keyboard rectangle tracking |
| Text field | `shell/surfaces/LauncherSurface.qml` | `TextInput` focus registration and `inputMethodHints` |
| Checks | `tests/keyboard.sh`, `tests/keyboard/check_layouts.py`, `tests/shell.sh` | config/layout/privacy checks and offscreen renders |
| Manual gate | `docs/qemu-keyboard-checklist.md` | real Squeekboard + Phosh checks in QEMU |

## Text-input protocol path

The keyboard is not a widget owned by each application. The flow is:

1. The application focuses a text field and binds `zwp_text_input_v3`. Qt's
   Wayland platform plugin does this for the shell's `TextInput` when the field
   has active focus.
2. Phosh's compositor (Phoc) sends the content purpose and hints to the active
   input method over `zwp_input_method_v2`.
3. Squeekboard selects a layout directory from the purpose:
   `terminal/`, `url/`, `pin/`, `email/`, `number/`, or the default directory.
4. Squeekboard commits text or keys through the input-method/virtual-keyboard
   protocols.
5. The compositor reports the keyboard rectangle to the application, and the
   application keeps the focused field visible.

This is why Squeekboard, not the Quickshell shell, is the right owner of the
system keyboard: a QML client cannot register an input method for other
applications. The shell's fallback panel only types into the shell's own
`TextInput`.

### Show and hide

With Squeekboard the compositor owns the policy:

- a text-input `enter`/focus event unfolds the keyboard;
- `leave`/blur hides it;
- the Phosh home bar (long-press/toggle) can show or hide it manually;
- `busctl call --user sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true`
  is available for a manual check.

The shell mirrors the common cases so it behaves well in both modes:

- `ShellState.attachKeyboard(target, purpose)` is called on `activeFocus`;
- `ShellState.detachKeyboard(target)` is called on focus loss;
- changing surface or locking calls `hideKeyboard()`;
- `Qt.inputMethod.show()` / `hide()` is used in compositor and auto modes.

### Keyboard avoidance

`shell.qml` computes a single `keyboardInset`:

- in inline/auto-fallback mode it is the fallback panel height;
- in compositor mode it is the keyboard height reported through
  `InputMethod.keyboardRectangle`, clamped to 45% of the window height;
- when an external Wayland keyboard does not report a rectangle (the common
  case for a compositor OSK), the shell reserves a conservative fraction of
  the window while a text field is focused: 40% portrait or 34% landscape;
- the shell body gets that value as a bottom margin. Navigation and content
  shrink above the keyboard instead of being painted underneath it;
- `PADILHA_SHELL_KEYBOARD_INSET=0.25` overrides the conservative fraction
  (clamped to 0-0.60) for a display or keyboard with different proportions;
- offscreen renders disable the compositor fraction and use the inline panel
  for their inset, so tests do not reserve space for a keyboard that is not
  drawn.

The panel itself is anchored to the window bottom. The launcher search field is
near the top, so it remains visible in both orientations. Any future field at
the bottom of a scrollable surface must use a `Flickable`/`ScrollView` and
scroll the focused item into the remaining body area; the global inset is a
reserve, not a substitute for a surface-specific scroll.

### Orientation

Squeekboard uses the `_wide` layout file when the panel is wide. The Padilha
set therefore has:

- `us.yaml` / `us_wide.yaml` for normal text and password fields;
- `terminal/us.yaml` / `terminal/us_wide.yaml` for terminals;
- `url/us.yaml` / `url/us_wide.yaml` for URL bars;
- `pin/us.yaml` / `pin/us_wide.yaml` for numeric secrets.

The installer applies the portrait/landscape scale settings only with
`--apply-settings`; it never changes the input source. The reference image uses
the US keymap (`keymap = us`), so the Padilha US files override the built-in US
layouts while other language layouts remain upstream.

## Layout semantics

### Default and password

Squeekboard has no separate `password/` hint directory. A Wayland
`content-purpose=password` field uses the default layout plus the
`sensitive_data` content hint, and the compositor hides the typed characters.
The default Padilha layout has letters, a numbers view, common punctuation,
space, backspace and return. It intentionally has no prediction, history,
clipboard or suggestion row.

### Terminal

The terminal layout adds a utility row with `Tab`, `Ctrl`, `Alt`, `Shift` and
arrow keys. It keeps `/`, `-`, `|` and a numbers view with the rest of the shell
punctuation. The wide variant also has an action view with function keys,
`Esc`, `Home`, `End`, `PageUp`, `PageDown`, `Insert`, `Delete` and modifiers.

These are Squeekboard keysyms/modifiers, not shell shortcuts: they go to the
focused terminal application through the compositor.

### URL

The URL layout keeps `/`, `.` and `:` on the home view and exposes `@ # $ % &
- _ + ( )`, quotes, brackets and the remaining URL punctuation in the numbers
and symbols views. It is designed for a browser address bar, not for prose.

### PIN

The PIN layout is a 3x4 digit grid with backspace and return. It is selected by
`content-purpose=pin`, not by the shell's own prototype lock screen (which uses
its own `PinPad` and is not authentication).

## Installation and activation

The image installs the `squeekboard` package through
`config/keyboard/keyboard.conf` (`KEYBOARD_PACKAGE`). In an existing guest,
install the layouts as the desktop user:

```sh
cd <checkout>
scripts/install-squeekboard.sh --apply-settings
```

This writes under `$XDG_DATA_HOME/squeekboard/keyboards` (normally
`~/.local/share/squeekboard/keyboards`) and applies unprivileged gsettings. It
does not need root and does not use `sudo`, `pkexec`, `systemctl`, `pacman` or
`mount`. Restart Squeekboard or re-open a text field after changing layouts.

If Phosh starts `phosh-osk-stub`/Stevia instead of Squeekboard, select the
Squeekboard OSK desktop entry (or stop the alternative keyboard in the user
session) before running the manual checklist. Do not disable the compositor's
text-input support.

## Privacy contract

- The shell does not write typed text to disk and does not log it. `appQuery`
  and the prototype PIN are in-memory UI state only; the PIN is a stub and is
  not authentication.
- The Squeekboard layouts contain no history, clipboard or prediction row.
- The policy keys `KEYBOARD_ENABLE_PREDICTION`,
  `KEYBOARD_ENABLE_SPELLCHECK`, `KEYBOARD_STORE_TYPED_TEXT` and
  `KEYBOARD_LOG_TYPED_TEXT` are all `false`.
- `tests/keyboard/check_layouts.py` scans the shell for logging of
  `TextInput.text`, the keyboard target or password/query state.
- Do not type a real password during a QEMU check. Use the disposable marker in
  the [checklist](qemu-keyboard-checklist.md).

This is a repository policy and a check, not a formal security audit of every
application in the guest.

## Test hooks

The shell fallback is opt-in so it does not double up with Squeekboard:

| Variable | Effect |
| --- | --- |
| `PADILHA_SHELL_OSK=compositor` | default: use the compositor keyboard, no inline panel |
| `PADILHA_SHELL_OSK=inline` | force the in-shell fallback panel |
| `PADILHA_SHELL_OSK=auto` | use the compositor keyboard if reported, otherwise fall back after 700 ms |
| `PADILHA_SHELL_OSK=off` | do not request or draw a shell keyboard |
| `PADILHA_SHELL_KEYBOARD=1` | force the fallback panel for a screenshot/test |
| `PADILHA_SHELL_KEYBOARD_PURPOSE=text\|terminal\|url\|password` | initial fallback layout purpose |
| `PADILHA_SHELL_KEYBOARD_VIEW=base\|upper\|numbers\|symbols` | initial fallback view |
| `PADILHA_SHELL_KEYBOARD_INSET=0.0-0.60` | override the conservative compositor keyboard reserve |

The fallback panel is installed with the `shell/` prototype, not with
Squeekboard. It is intentionally small: it covers the shell's own fields and
is useful for offscreen rendering and desktop development. It is not a
replacement for a system input method.

## What is verified

`make test` / `tests/all.sh` includes `tests/keyboard.sh`, which checks:

- the ADR decision and documentation links;
- the config backend/package, show/hide policy and privacy flags;
- every layout parses as YAML (PyYAML when present; a dependency-free parser
  otherwise) and has the required terminal/URL/PIN keys;
- the installer copies the expected files to a temporary user directory and
  its dry run changes nothing;
- no keyboard tooling calls a privileged command;
- no shell code logs typed text.

`tests/shell.sh` also renders the fallback keyboard at 720x1280 and 1280x720
for text, terminal, URL and password purposes. The visual check confirms the
PNG is not blank and the shell logs no QML errors.

Real Squeekboard behaviour needs the QEMU gate in
[`qemu-keyboard-checklist.md`](qemu-keyboard-checklist.md). No physical-device
claim is made by these checks.
