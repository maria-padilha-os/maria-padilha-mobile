# ADR 0004: Camera and media capture

- **Status:** accepted for the camera milestone
- **Date:** 2026-11-11
- **Supersedes:** none
- **Related:** [ADR 0001](0001-mobile-base-and-reference-device.md)

## Context

The reference image is postmarketOS/Nura stable with Phosh on aarch64, with
`qemu-aarch64` as the first validation target. The physical target remains a
PinePhone-class close-to-mainline handset, but ADR 0001 explicitly does not
claim camera support: the camera is partial, the front camera has no mainline
driver on the original PinePhone, and sensor/ISP tuning is device-specific.

Camera support is therefore a stack and permission decision, not a promise
that every phone camera works. The repository needs to:

- integrate the maintained Linux camera stack rather than a vendor daemon;
- put a real permission boundary between applications and camera devices;
- render a clear no-camera state instead of crashing or showing a fake photo;
- provide a reproducible test pattern for QEMU and automated checks;
- avoid publishing private photos or a bundled "sample" image.

## Options considered

### 1. libcamera + PipeWire + xdg-desktop-portal + Padilha surface (chosen)

`libcamera` enumerates sensors and ISPs through the kernel media controller.
The `pipewire-spa-libcamera` SPA plugin publishes those cameras as PipeWire
video nodes. `xdg-desktop-portal`'s Camera interface is the permission
boundary: an application calls `AccessCamera`, waits for `Request.Response`,
and only then calls `OpenPipeWireRemote` to obtain a PipeWire file descriptor.
A small Padilha camera surface consumes the portal-gated stream and renders
the states.

This is the same architecture used by modern Linux camera applications. It
keeps the application unprivileged, avoids a second camera daemon, and lets
the session's portal backend own the user prompt and per-application access.

### 2. Direct V4L2 / vendor camera HAL

A direct `/dev/video*` or vendor HAL path would work on some devices sooner,
but it bypasses the portal permission boundary, needs device-specific
userspace, and would make the image depend on blobs and udev rules that cannot
be reviewed here. It also gives no consistent answer for QEMU, which has no
camera device. Rejected as the default; no direct V4L2 path is shipped.

### 3. GNOME Snapshot as the only camera application

GNOME Snapshot (`snapshot`) is a maintained libadwaita camera application and
is a reasonable optional package on a GNOME/Phosh image. It would still use
the same libcamera/PipeWire/portal stack. It is a larger dependency than the
Padilha shell prototype needs, it does not provide the Padilha permission and
fallback states, and installing it would not by itself prove any device
camera. It remains an optional future package, not the repository-owned camera
surface.

### 4. libcamera or GStreamer direct, without the portal

This is simpler to prototype but makes permission handling advisory. A
malicious or buggy application could open the camera without a user-visible
decision. The repository would then have to implement its own permission
store and UI. Rejected: `xdg-desktop-portal` already provides the boundary.

### 5. Android camera HAL or camera2

Android is not the base selected by ADR 0001. A compatibility layer would add
a second camera stack and a much larger image for no demonstrated benefit.
Rejected.

## Decision

Use this stack:

| Layer | Component | Responsibility |
| --- | --- | --- |
| Hardware | kernel media controller + sensor driver | device-specific enumeration and tuning |
| Camera library | `libcamera` | sensor/ISP control and buffer production |
| Transport | PipeWire + `pipewire-spa-libcamera` | camera nodes and buffers in the session |
| Session | `wireplumber` | PipeWire policy and node management |
| Permission | `xdg-desktop-portal` + `xdg-desktop-portal-gnome` | user decision and portal PipeWire remote |
| Capture helper | [`scripts/camera-bridge.py`](../../scripts/camera-bridge.py) | state, permission request, one-frame capture, generated pattern |
| UI | [`shell/surfaces/CameraSurface.qml`](../../shell/surfaces/CameraSurface.qml) | preview, permission, capture and graceful states |
| Policy | [`config/camera/camera.conf`](../../config/camera/camera.conf) | packages, portal names, privacy flags |

The image adds `libcamera`, `libcamera-tools`, `pipewire`, `pipewire-spa-libcamera`,
`wireplumber`, `xdg-desktop-portal`, `xdg-desktop-portal-gnome` and the
GStreamer PipeWire elements used by the one-frame capture helper. The
repository does not build a camera daemon, install a udev rule for a specific
sensor, or modify the portal backend.

The Padilha shell starts one short-lived helper per action. The helper is not
a daemon:

```
--state        report portal/PipeWire/libcamera availability (no prompt)
--request      AccessCamera -> Request.Response -> OpenPipeWireRemote
--capture      the same permission flow, then one PipeWire frame to PNG
--test-pattern generate a deterministic PNG; no camera and no portal
```

The camera UI requests access when the camera surface is opened (unless
`PADILHA_CAMERA_AUTOREQUEST=0`) and offers an explicit **Allow camera** action
after a denial or cancellation. There is no retry loop and no silent direct
device access.

## Consequences

- The application is unprivileged and never needs to be in the `video` group
  to use the supported path.
- QEMU has no camera device by default. A QEMU run validates the portal
  absence, no-camera state and generated pattern, not camera capture.
- A device needs a mainline sensor driver, a working libcamera pipeline and the
  PipeWire SPA plugin before the UI can show a frame. That is per-device work
  and is not claimed by this task.
- The portal backend and its user prompt are part of the security boundary.
  A session without `xdg-desktop-portal` does not get live capture; it falls
  back to the labelled test pattern.
- A one-frame capture uses the PipeWire fd returned by the portal and
  `gst-launch-1.0 pipewiresrc`. This is a deliberately small app, not a video
  recorder. Continuous preview and recording remain future work.
- The camera surface and helper add no persistent cache and no gallery
  integration. Captures live in `$XDG_RUNTIME_DIR/maria-padilha-camera` and
  are removed with the session.

## Privacy contract

- `CAMERA_STORE_CAPTURES=false`, `CAMERA_UPLOAD_CAPTURES=false`,
  `CAMERA_LOG_IMAGE_DATA=false`, `CAMERA_LOG_CAPTURE_PATHS=false` and
  `CAMERA_BUNDLE_TEST_IMAGES=false`.
- No photograph, screenshot, sample camera image or generated test image is
  committed to the repository. The fallback is drawn by the QML canvas or
  generated on demand in a temporary directory.
- The bridge writes image bytes only to the capture file. It never prints
  frame contents, a capture path, a portal request token or a remote error
  message to stderr or a journal.
- Camera QML contains no `console.log`, `console.warn` or `console.error`.
- The test suite uses the emulated portal and the generated pattern; it never
  opens the host camera or captures the desktop.
- The generated pattern contains the text `generated test pattern; not a
  photograph or camera image` in a PNG text chunk so it cannot be mistaken
  for a photo.

## Unsupported cases

- No physical camera is qualified by this ADR.
- No front-camera support is claimed.
- No continuous preview, video recording, audio recording, flash, focus
  control, zoom, HDR or image processing is implemented.
- No MIPI/CSI sensor, ISP or media-controller tuning is added.
- No Android camera HAL, vendor blob or proprietary camera service is used.
- No direct V4L2 fallback is shipped; direct access would bypass the portal.
- No camera access is granted to the shell itself outside the portal flow.

## Risks for the next tasks

1. **Per-device camera plumbing dominates.** Even with the stack in place, a
   handset may have no mainline sensor driver or a broken libcamera pipeline.
2. **Portal backend availability differs by session.** Phosh commonly uses
   `xdg-desktop-portal-gnome`; a minimal session may need another backend.
3. **PipeWire node naming is not uniform.** The capture helper accepts an
   optional `--camera-node` target, but camera selection UI is not built.
4. **The one-frame capture is not a preview.** Continuous video needs a
   PipeWire consumer with a frame sink, not repeated `gst-launch` processes.
5. **The portal fd is a security boundary.** Future work must keep using
   `OpenPipeWireRemote` rather than opening the session PipeWire or
   `/dev/video*` directly.
6. **Test patterns are not evidence of a camera.** A green QEMU fallback run
   must never be recorded as camera hardware support.

## No real camera claim

No camera was available for this task. The automated checks use an emulated
`org.freedesktop.portal.Camera` service, a generated PNG test pattern and QML
renders. They do not capture a photograph, open a physical sensor, prove
libcamera enumeration, prove the portal prompt, or qualify any device. The
manual gate is [`docs/qemu-camera-checklist.md`](../qemu-camera-checklist.md).
A pass there must name the device, kernel, sensor, libcamera version, portal
backend and whether the frame was actually captured.

## Sources

- libcamera project: <https://libcamera.org/>
- PipeWire documentation: <https://docs.pipewire.org/>
- xdg-desktop-portal Camera API:
  <https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Camera.html>
- PipeWire libcamera SPA plugin package:
  <https://pkgs.alpinelinux.org/package/edge/community/aarch64/pipewire-spa-libcamera>
- postmarketOS package index: <https://pkgs.postmarketos.org/packages>
- ADR 0001, mobile base and reference device:
  [0001-mobile-base-and-reference-device.md](0001-mobile-base-and-reference-device.md)
