# Manual QEMU keyboard checklist

This is the hardware-free gate for the on-screen keyboard. Run it inside the
checked `qemu-aarch64` Phosh image described in [Building](build.md). It does
not flash, partition or claim support for a physical phone.

Record the image checksum (`out/maria-padilha-qemu-aarch64.img.sha256`), the
QEMU command, the date, and pass/fail for each row. A skipped row is not a
pass. If the QEMU display or Phosh session cannot rotate, record orientation as
unverified instead of claiming it.

## 1. Prepare the guest

- [ ] Boot the image with `scripts/run-qemu.sh` and wait for the Phosh session.
- [ ] Copy this checkout into the guest, or use the guest shared folder.
- [ ] Confirm the keyboard package is installed (unprivileged query):

  ```sh
  apk info -e squeekboard
  ```

- [ ] Confirm the compositor exposes the text-input and keyboard protocols:

  ```sh
  wayland-info | grep -E 'zwp_text_input|zwp_input_method|zwp_virtual_keyboard'
  ```

  Expect `zwp_text_input_manager_v3`, `zwp_input_method_manager_v2` and
  `zwp_virtual_keyboard_manager_v1` (Phosh/Phoc versions may expose the exact
  names with a version suffix).
- [ ] Install the Padilha layouts and settings as the desktop user:

  ```sh
  cd <checkout>
  scripts/install-squeekboard.sh --apply-settings
  ```

  This is unprivileged and writes under
  `~/.local/share/squeekboard/keyboards`.
- [ ] Confirm the active OSK process:

  ```sh
  pgrep -a squeekboard
  ```

  If the image starts `phosh-osk-stub`/Stevia instead, select the Squeekboard
  OSK entry for the session or stop the alternative keyboard, then repeat.
  Record which process was active; do not claim Squeekboard if it was not.
- [ ] Confirm the screen-keyboard setting and layout directory:

  ```sh
  gsettings get org.gnome.desktop.a11y.applications screen-keyboard-enabled
  find ~/.local/share/squeekboard/keyboards -type f | sort
  ```

  Expect `true`, `us.yaml`, `us_wide.yaml`, `terminal/us.yaml`, `terminal/us_wide.yaml`,
  `url/us.yaml`, `url/us_wide.yaml`, `pin/us.yaml` and `pin/us_wide.yaml`.

## 2. Text-input protocol and show/hide

- [ ] Open a terminal application and tap its text area. The keyboard unfolds
  automatically and the terminal cursor stays active.
- [ ] Tap outside the terminal (or another window). The keyboard hides.
- [ ] Tap the terminal field again. The keyboard returns without losing the
  text already entered.
- [ ] Long-press/toggle the Phosh home bar. The keyboard hides and shows again.
- [ ] Manual show/hide check (optional, unprivileged user bus):

  ```sh
  busctl call --user sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true
  busctl call --user sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false
  ```

- [ ] Lock the shell (Lock surface). No keyboard remains over the lock screen.

## 3. Purpose-specific layouts

Use disposable text only. Never type a real password, PIN, token or private
message during this checklist.

### Terminal

- [ ] Focus a terminal field and record the visible utility row.
- [ ] `Tab`, `Ctrl`, `Alt`, `Shift` and the four arrow keys are present and
  send the expected terminal keys (`Tab` completes, arrows move the cursor).
- [ ] `/`, `-`, `|` and the numbers view are reachable in one or two taps.
- [ ] In landscape, the terminal `>_` action view opens and provides function
  keys, `Esc`, `Home`, `End`, `PageUp`, `PageDown`, `Insert` and `Delete`.

### URL

- [ ] Focus a browser address bar. The URL layout appears, with `/`, `.` and
  `:` on the home view.
- [ ] The numbers/symbols views provide `@ # $ % & - _ + ( )`, quotes, brackets
  and the remaining URL punctuation.
- [ ] Type a short disposable URL and confirm Return commits it.

### Password

- [ ] Focus a password field (a scratch form, not a real account).
- [ ] Typed characters are hidden by the application, and the keyboard shows no
  suggestion, history or clipboard row.
- [ ] The keyboard still has letters, digits and symbols; backspace and Return
  work.
- [ ] A numeric PIN field uses the 3x4 `pin/` layout with digits, backspace and
  Return. This is a layout check, not authentication.

## 4. Orientation and keyboard avoidance

### Portrait (720x1280 reference)

- [ ] Focus the topmost field (launcher search or terminal). The field remains
  above the keyboard's top edge.
- [ ] Focus the lowest field in a scrollable surface. The surface scrolls or
  shrinks so the field is not covered; the cursor and the line being edited are
  visible.
- [ ] The keyboard spans the window width and the navigation/content area ends
  above it rather than underneath it.
- [ ] No key is clipped at the left or right edge; every key target is at least
  48 px.

### Landscape (1280x720 reference)

- [ ] Rotate the Phosh session (quick settings rotation, or the compositor's
  output transform). If rotation is unavailable in the QEMU display, mark this
  section unverified.
- [ ] The wide keyboard is used, with a shorter panel that leaves the focused
  field visible.
- [ ] The side rail/navigation is not painted under the keyboard.
- [ ] The terminal utility row and the URL/password home rows still fit without
  clipped labels.
- [ ] Rotate back to portrait; the keyboard hides or reflows without leaving a
  stale inset.

## 5. Privacy spot-check

This is a smoke check, not a formal audit.

- [ ] Do not type a real secret. Use the disposable marker
  `padilha-keyboard-probe-not-secret` in a scratch field.
- [ ] Check the user journal for the marker:

  ```sh
  journalctl --user --since "10 min ago" --no-pager | grep -F padilha-keyboard-probe-not-secret
  ```

  Expect no output. If the marker appears, record which component logged it and
  treat the privacy row as failed.
- [ ] Confirm the layout directory contains only YAML layouts and no captured
  text:

  ```sh
  find ~/.local/share/squeekboard/keyboards -type f -maxdepth 3 -print
  ```

- [ ] Confirm the shell does not write the launcher query or prototype PIN to
  disk. Search its state/log locations for the marker; expect no match.

## 6. Result record

| Area | Portrait | Landscape | Notes |
| --- | --- | --- | --- |
| OSK process and package | | | |
| Text-input protocol (`zwp_text_input_v3` etc.) | | | |
| Show on focus / hide on blur | | | |
| Home-bar toggle | | | |
| Terminal layout | | | |
| URL layout | | | |
| Password layout | | | |
| PIN layout | | | |
| Focused field not covered | | | |
| No typed-text logging | | | |

**QEMU only.** No physical-device claim is made by this checklist. PinePhone
support stays deferred until the separate physical gate in ADR 0001 passes on
real hardware.
