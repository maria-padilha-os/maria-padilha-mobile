# ADR 0002: On-screen keyboard and text input

- **Status:** Accepted
- **Date:** 2026-11-08
- **Decision owner:** Maria Padilha Mobile maintainers
- **Related:** [ADR 0001](0001-mobile-base-and-reference-device.md),
  [Keyboard integration](../keyboard.md),
  [Manual QEMU checklist](../qemu-keyboard-checklist.md)

## Context

Maria Padilha Mobile is a touch-first Phosh image. A phone shell must be able
to show a keyboard when a text field is focused, carry the text-input content
purpose (normal text, URL, password, terminal, PIN) to a layout that suits it,
and hide the keyboard again without stealing focus or leaving typed text
behind. The keyboard also has to fit under Phosh in both portrait and
landscape, and it must not cover the field that is being edited.

The image already selects postmarketOS/Nura stable, Phosh and systemd in
[ADR 0001](0001-mobile-base-and-reference-device.md). Phosh owns the Wayland
compositor session, so the keyboard is a compositor/input-method component,
not a widget that every application must embed. The two candidates in this
decision are **Squeekboard** and **Maliit Keyboard**. Newer Phosh releases may
also ship `phosh-osk-stub` ("Stevia"); it is noted under consequences but is
not a third choice in this task.

The relevant Wayland path is:

1. an application focuses a text field and binds `zwp_text_input_v3`;
2. the compositor passes content purpose/hints to the active input method over
   `zwp_input_method_v2`;
3. the input method draws a keyboard and commits text/keys through the
   protocol, with `zwp_virtual_keyboard_v1` as the legacy fallback;
4. the compositor reports the keyboard rectangle back to the application, so
   the application can keep the focused field visible.

## Decision

**Choose Squeekboard** as the on-screen keyboard for the first Maria Padilha
Mobile image.

The image installs the `squeekboard` package explicitly and ships Padilha
layouts for the US reference keymap. The shell keeps a small in-process
fallback panel for development and for a compositor that does not expose a
keyboard, but Squeekboard is the primary backend for terminals, URL bars,
password fields and other applications.

## Options considered

### Comparison

Scores are 1 (poor fit) to 5 (first-class fit) and are judgment calls, not
measurements. The weights reflect the M1 target: Phosh is already fixed by
ADR 0001, the QEMU reference is the only validation target, and no physical
device is claimed.

| Criterion | Weight | Squeekboard | Maliit Keyboard |
| --- | ---: | ---: | ---: |
| Phosh/Phoc integration | 30% | 5 | 2 |
| Text-input protocol and hints | 20% | 5 | 4 |
| Terminal/URL/PIN layouts | 15% | 5 | 3 |
| Touch/stylus and orientation | 15% | 4 | 4 |
| Packaging and maintenance on Nura | 10% | 5 | 3 |
| Privacy and data handling | 10% | 5 | 3 |
| **Weighted result** | | **4.85** | **3.05** |

The result is not close enough to justify a second keyboard stack or a
custom input-method implementation.

### Phosh/Phoc integration

**Squeekboard.** Squeekboard is the Phosh on-screen keyboard. It is designed
for Phosh's compositor (`phoc`), uses layer-shell plus the virtual-keyboard
protocol, and recommends the input-method-v2 protocol. Phosh knows how to
start it, show it on text-input activation, hide it on blur and toggle it from
the home bar. The Nura Phosh UI already carries an OSK dependency, so
installing Squeekboard adds a supported component rather than a second
integration.

**Maliit Keyboard.** Maliit is a capable Qt/QML keyboard and is the Plasma
Mobile default. Its Wayland path was built around KWin's input-method and
text-input integration. Phosh does not ship Maliit as its input method, and
there is no first-class "enable Maliit in Phosh" switch: the compositor glue,
OSK startup, and DBus/OSK arbitration have to be supplied and maintained by
us. That is exactly the kind of device/session integration ADR 0001 chose not
to invent for M1.

### Text-input protocol and hints

**Squeekboard.** It consumes `text-input-unstable-v3` purpose and hint values
and chooses hint directories: `terminal/`, `url/`, `email/`, `pin/`, `number/`
and the default layout. It also supports the virtual-keyboard fallback for
legacy clients. Content purpose arrives as a normal part of the protocol; the
application does not need a proprietary key or a shell-specific API.

**Maliit.** It supports text-input v3 in current releases and has a Qt input
context, but on Phosh the compositor has to connect it to the same protocol and
forward purpose/hints. The protocol support is not the problem; the missing
Phosh session integration is.

### Terminal, URL and password layouts

**Squeekboard.** Layouts are declarative YAML and are selected by content
purpose. A terminal layout can include Tab, Ctrl, Alt, Shift, arrows, `/`, `-`,
`|` and a `>_` action view. A URL layout can keep `/`, `.` and `:` on the home
view and expose the rest of the URL punctuation in the numbers view. Password
fields use the default layout plus the `sensitive_data` content hint; there is
no prediction engine in Squeekboard, so there is no completion history to
clear. PIN fields use the numeric `pin/` layout. This gives the three requested
use cases without patching the keyboard source.

**Maliit.** Maliit has layouts and plugins, including terminal-friendly and
numeric keyboards, but the exact layout set depends on the Maliit plugins and
the Plasma/Phosh packaging. Its word-prediction and correction plugins add
state and configuration that would need an explicit privacy review on our
image. Those features are useful for general typing but are not needed for the
first terminal/URL/password milestone.

### Touch, stylus and orientation

Both keyboards are touch-first. Squeekboard ships compact (`12:7`) and wide
(`16:5`) arrangement variants and can stretch a layout to the panel. It has
GSettings for portrait and landscape scale and for fit-to-panel behaviour, which
lets the same layout work in both orientations. Maliit also adapts to screen
size and orientation, but its panel sizing is managed through Plasma's
input-method integration rather than Phosh's.

Squeekboard wins this row narrowly because its orientation settings are
documented and configurable in the Phosh stack we already use, not because
Maliit is unusable with a touchscreen.

### Packaging and maintenance on Nura

**Squeekboard.** It is packaged for Alpine/Nura as `squeekboard` and is part of
the Phosh ecosystem. We pin the package in `config/build.conf` through
`config/keyboard/keyboard.conf`. Layout files are data, so a Padilha layout
change does not require rebuilding a keyboard binary.

**Maliit.** `maliit-keyboard` and its framework/plugin packages are available
in Alpine, but the full Plasma/Qt input-method stack and its configuration are
not part of a Phosh image. Choosing it would mean owning that extra stack and
its upgrade path on a 2-3 GB reference class device.

### Privacy and data handling

**Squeekboard.** No text prediction engine is present today, and the layouts
we ship contain no history, clipboard or suggestion row. The keyboard receives
text through the input-method protocol but does not persist it. The Padilha
policy records `KEYBOARD_STORE_TYPED_TEXT=false` and
`KEYBOARD_LOG_TYPED_TEXT=false`, and the repository checks scan for logging of
typed fields. Password fields are handled with the compositor's sensitive-data
hint.

**Maliit.** Maliit's prediction and correction plugins can keep word models and
completion state. That can be disabled, but it is another privacy surface to
audit and to keep disabled across upgrades. It is not a reason to reject
Maliit forever; it is a reason not to add it when Squeekboard already has no
prediction engine.

## Consequences

Positive:

- one Phosh-native keyboard instead of a second Qt input-method stack;
- declarative layouts for terminal, URL and PIN, plus a default layout for
  password and ordinary text;
- content-purpose and text-input-v3 handling come from the compositor/Phosh;
- orientation settings and a wide layout are configuration, not code;
- no typed-text persistence or logging in the shell or the layouts.

Negative:

- Squeekboard is GTK3 while the Padilha shell is Qt/QML, so the shell's inline
  fallback cannot reuse Squeekboard code and Squeekboard cannot reuse the QML
  palette directly; the Padilha theme layer styles GTK separately.
- Squeekboard has no text prediction or swipe typing. That is intentional for
  this milestone, but it is a real usability gap for general typing.
- Recent Phosh releases may prefer `phosh-osk-stub`/Stevia. The QEMU checklist
  therefore verifies which OSK process is active and explicitly starts/selects
  Squeekboard if the image defaults to Stevia. If Stevia becomes the only
  supported Phosh keyboard, this ADR must be revisited rather than silently
  changing the backend.
- The shell's inline fallback is not a system-wide input method: it can only
  type into the shell's own `TextInput`. External applications always use the
  compositor keyboard.

## Verification

The decision is verified without hardware:

- `tests/keyboard.sh` checks the config, both orientations' layout files, the
  terminal/URL/PIN key sets, the no-storage/no-logging policy, and the
  unprivileged installer;
- `tests/shell.sh` renders the inline fallback at 720x1280 and 1280x720 for
  text, terminal, URL and password purposes;
- the [manual QEMU checklist](../qemu-keyboard-checklist.md) verifies the real
  Squeekboard process, text-input protocol, show/hide, both orientations and
  keyboard avoidance inside the guest.

No physical device was used, and none of these checks is a hardware support
claim.

## Sources

Checked 2026-11-08. These are upstream project statements, not measurements
from this repository.

- Squeekboard README: text-input/virtual-keyboard protocols, YAML layouts,
  layer-shell and input-method-v2 requirements:
  <https://gitlab.gnome.org/World/Phosh/squeekboard/-/blob/main/README.md>
- Squeekboard layout guide, including the supported hint directories:
  <https://gitlab.gnome.org/World/Phosh/squeekboard/-/blob/main/doc/layouts.md>
- Squeekboard layout tutorial and custom-layout install path:
  <https://gitlab.gnome.org/World/Phosh/squeekboard/-/blob/main/doc/tutorial.md>
- `phosh-osk-stub` manual page, including its text-input-v3/input-method-v2
  mode, terminal layouts and relationship to Squeekboard:
  <https://manpages.debian.org/experimental/phosh-osk-stub/phosh-osk-stub.1.en.html>
- Plasma Mobile's Maliit switch and the KWin input-method/text-input work:
  <https://plasma-mobile.org/2020/10/09/plasma-mobile-update-september/>
- Phosh issue asking whether Maliit can be enabled in Phosh, showing that it is
  not a first-class Phosh backend:
  <https://gitlab.gnome.org/World/Phosh/phosh/-/work_items/807>
- Wayland text-input-unstable-v3 protocol:
  <https://wayland.app/protocols/text-input-unstable-v3>
- Wayland input-method-unstable-v2 protocol:
  <https://wayland.app/protocols/input-method-unstable-v2>

## Revision history

- 2026-11-08: accepted. Squeekboard selected for the QEMU-first Phosh image;
  Maliit documented as the fallback if Phosh's OSK stack changes.
