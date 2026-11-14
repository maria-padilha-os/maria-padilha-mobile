# Manual QEMU camera checklist

This is the manual gate for camera and media capture. It is **not** run by the
repository tests, and this checkout does not claim a real camera, a real portal
prompt or physical-device support.

QEMU's `qemu-aarch64` reference machine has **no camera device by default**.
The QEMU part of this checklist therefore validates only the no-camera state,
the generated test pattern and graceful portal handling. Live capture is a
supported-device or passed-through-camera result, and only after the
[supported-device note](camera-supported-devices.md) is updated with evidence.

## Preconditions

- The checked `qemu-aarch64` image is built and booted by the documented
  builder path in [`docs/build.md`](build.md), or you are on a supported device
  with a mainline camera pipeline.
- The image contains `libcamera`, `pipewire`, `pipewire-spa-libcamera`,
  `wireplumber`, `xdg-desktop-portal`, `xdg-desktop-portal-gnome` and the
  GStreamer PipeWire elements (`config/camera/camera.conf`).
- The checkout is available inside the guest for the shell, bridge and
  diagnostic commands.
- **Do not use a private photo or a real personal scene for this check.** Use
  the generated pattern or a disposable label such as a printed
  `padilha-camera-check-<random>` card. Delete captures after the check.
- Do not publish a captured frame, a screenshot of a frame or a test image in
  the repository, an issue or a release.

## 1. Host-side checks

```sh
make check
make camera-test
make shell-test
```

Expected: all pass. The camera test output says the emulated Camera portal
exercised grant, deny, cancel, no-camera, no-portal and the generated pattern.
Those lines are **not** a hardware result.

## 2. Guest sees the stack

Inside the guest:

```sh
scripts/camera-bridge.py --state
scripts/camera-bridge.py --test-pattern /tmp/padilha-camera-pattern.png
```

Expected on a guest with no camera:

- `--state` exits 0 and prints one JSON object.
- `portal.available` is `true` if `xdg-desktop-portal` is running.
- `portal.cameraPresent` is `false` on a QEMU guest without a passed-through
  camera; the state is `no-camera`.
- If the portal is absent, the state is `unavailable` or `portal-unavailable`
  and `fallback` is `test-pattern`; that is a pass for graceful handling.
- `--test-pattern` writes a PNG and prints `"generated":true`. The PNG must be
  a colour-bar/checkerboard pattern, not a photo.

Optional read-only inspection (no root required):

```sh
pw-dump | grep -i -m1 'Video/Source'
cam -l
```

If `cam` or a PipeWire camera node is absent, record that as an environment
result, not a failure of the fallback.

## 3. No-camera UI state

Open the shell in the guest:

```sh
PADILHA_SHELL_DEMO=0 PADILHA_CAMERA_DEMO=0 PADILHA_CAMERA_BACKEND=auto \
  quickshell -p "$PWD/shell"
```

Open **Camera** from the app grid or with:

```sh
qs ipc call padilha-shell camera
```

Expected:

- the surface shows **No camera** with an explanation;
- the preview is labelled **Generated test pattern**, not a camera image;
- **Allow camera** is absent because no camera is present;
- **Show test pattern** remains available;
- the shell stays responsive and no helper process is left running;
- `qs ipc call padilha-shell status` reports `camera` `no-camera` (or
  `unavailable`) and `cameraPresent` false, with no image path.

Then test the explicit backend-off path:

```sh
PADILHA_SHELL_DEMO=0 PADILHA_CAMERA_DEMO=0 PADILHA_CAMERA_BACKEND=off \
  quickshell -p "$PWD/shell"
```

Expected: **Camera backend disabled**, generated pattern only, no process.

## 4. Portal permission path

Only continue if `scripts/camera-bridge.py --state` reports
`portal.cameraPresent: true`. On a QEMU guest this normally requires a
passed-through or emulated camera; do not expect it on the default machine.

1. Open **Camera** with `PADILHA_CAMERA_AUTOREQUEST=0`.
2. Confirm the surface shows **Camera ready** and an **Allow camera** button.
3. Press **Allow camera**.
4. The session portal should show its own camera permission prompt.
5. Grant or deny it and record which response appeared.

Expected:

- a grant moves the surface to **Camera ready** with an **Allowed** badge and
  a **Capture** button;
- a denial shows **Camera access denied**, keeps the generated pattern and
  does not retry in a loop;
- a cancellation shows **Camera access cancelled**;
- the helper never falls back to `/dev/video*`.

The emulated portal in `tests/camera/fake_camera_portal.py` is the automated
equivalent. It is not a real prompt.

## 5. Capture check on a camera-equipped device or guest

Use a generated target (the test pattern on screen or a printed marker), never
a private photo.

1. With permission granted, press **Capture**.
2. Confirm the surface says **Camera frame** and displays the captured frame.
3. Confirm the frame is the generated target, not a desktop screenshot.
4. Run the capture helper directly once:

   ```sh
   scripts/camera-bridge.py --capture /tmp/padilha-camera-frame.png
   ```

5. Confirm the JSON has `"type":"capture"`, `"ok":true`, `"source":"camera"`
   and a plausible width/height.
6. Delete both temporary files:

   ```sh
   rm -f -- /tmp/padilha-camera-frame.png /tmp/padilha-camera-pattern.png
   ```

Expected with a working camera stack: one frame is written and displayed. If
the portal grants access but `capture-failed` is reported, record the sensor,
kernel, libcamera and PipeWire versions; do not claim a camera pass.

## 6. Failure-state checks

Where the guest's services and test setup allow it, check at least:

- no camera (`no-camera`);
- portal absent (`portal-unavailable` or `unavailable`);
- permission denied (`permission-denied`);
- permission cancelled (`permission-cancelled`);
- capture pipeline failure (`capture-failed`).

Do not stop or restart a system service on a production device. Use a
disposable guest or the emulated portal for these states. The automated
`tests/camera.sh` gate (`make camera-test`) already covers them against the
fixture.

## 7. Privacy check

After generating or capturing a marker frame:

```sh
journalctl -b --no-pager | grep -F 'padilha-camera'
journalctl --user -b --no-pager | grep -F 'padilha-camera'
```

Expected: no capture path, image bytes, portal token or frame content in a
journal line. The bridge may print a JSON state on stdout for the shell; it
must not write image data to stderr or a log.

Also check that no captured file is inside the repository checkout:

```sh
git status --short
```

Expected: clean except for review edits. Captures belong in
`$XDG_RUNTIME_DIR` or a temporary directory, never in `docs/`, `tests/` or
`shell/`.

## Pass criteria

A camera gate passes only when:

- `make check`, `make camera-test` and `make shell-test` are clean;
- a no-camera guest renders the no-camera state and generated pattern without
  a crash or leftover process;
- the portal is detected and the permission grant, denial and cancellation
  states are all handled;
- on a camera-equipped target, one frame is captured and displayed;
- the captured frame is a generated target, not a private photo;
- no image, capture path or frame content appears in a log or the repository;
- failure states are graceful.

## No real camera claim

The repository-side tests use an emulated `org.freedesktop.portal.Camera`
service and a generated PNG. They do **not** open a real camera, prove the
portal prompt, prove libcamera sensor enumeration or qualify any phone. This
checklist is the only place where a real camera result may be recorded, and it
must name the device, kernel, sensor, libcamera version, PipeWire version,
portal backend and whether a frame was actually captured.

## No physical-device claim

A QEMU pass, with or without a passed-through camera, does not qualify a
PinePhone or any other handset. Physical support still needs the ADR 0001 gate:
SD boot, Phosh, touch, keyboard, Wi-Fi, audio, suspend/resume, modem, calls,
SMS, mobile data (carrier-dependent), camera, FDE and recovery on a real unit.
See the [camera supported-device note](camera-supported-devices.md).
