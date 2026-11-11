# Camera and media capture

Maria Padilha Mobile uses **libcamera** for sensor and ISP access, **PipeWire**
for camera transport, and **xdg-desktop-portal** for permission. The Padilha
camera surface is a small consumer of that stack, not a camera daemon and not
a vendor camera HAL. The decision is recorded in
[ADR 0004](adr/0004-camera-and-media-capture.md).

**No real camera was tested in this checkout.** The automated gate uses an
emulated `org.freedesktop.portal.Camera` service and a generated test pattern.
No photograph is bundled, captured or published. The device-specific gate is
the [QEMU/manual camera checklist](qemu-camera-checklist.md), and physical
support is governed by the [supported-device note](camera-supported-devices.md).

## Components

| Component | Path | Role |
| --- | --- | --- |
| Camera policy | `config/camera/camera.conf` | packages, portal names, permission and privacy flags |
| Image packages | `config/build.conf`, `scripts/build.sh` | adds the libcamera/PipeWire/portal package set |
| Camera bridge | `scripts/camera-bridge.py` | one-shot state, portal permission, frame capture and generated pattern |
| Emulated portal | `tests/camera/fake_camera_portal.py` | session-bus `org.freedesktop.portal.Camera` fixture; not a camera |
| Bridge checks | `tests/camera/test_camera_bridge.py` | state, grant/deny/cancel, no-camera, no-portal, capture pipeline, deterministic pattern |
| Camera service | `shell/components/CameraService.qml` | process lifetime, JSON projection, permission state and fallback |
| Camera surface | `shell/surfaces/CameraSurface.qml` | preview, permission action, capture action and explanations |
| Generated preview | `shell/components/CameraTestPattern.qml` | colour bars/checkerboard canvas, never a stored image |
| Checks | `tests/camera.sh`, `tests/shell.sh` | static policy, emulated portal flow, shell process and renders |
| Manual gate | `docs/qemu-camera-checklist.md` | supported-device or camera-equipped guest checks |

The image adds:

```
libcamera libcamera-tools pipewire pipewire-spa-libcamera wireplumber
xdg-desktop-portal xdg-desktop-portal-gnome
gstreamer gst-plugins-base gst-plugins-good gst-plugin-pipewire
```

`pipewire-spa-libcamera` is the SPA plugin that publishes libcamera cameras as
PipeWire nodes. `xdg-desktop-portal-gnome` is the Phosh/GNOME session backend;
`xdg-desktop-portal` itself is backend-independent. The GStreamer packages
provide `pipewiresrc`, `videoconvert`, `pngenc` and `gst-launch-1.0` for the
one-frame capture helper. No package is a repository-owned service.

The shell resolves the bridge relative to its own directory
(`Quickshell.shellPath("../scripts/camera-bridge.py")`). A packaged image must
install the bridge in that layout, install it at `CAMERA_BRIDGE`, or set
`PADILHA_CAMERA_BRIDGE` to the installed path. The current image builder does
not install the Quickshell prototype, so this is a packaging step for the shell
task rather than a root operation in this checkout.

## Permission flow

The portal is the only permission boundary. The bridge never opens
`/dev/video*`, and `CAMERA_DIRECT_V4L2=false` is enforced by the shared config
gate.

1. The camera surface calls the bridge with `--state`.
2. The bridge checks `org.freedesktop.DBus.NameHasOwner` for
   `org.freedesktop.portal.Desktop` and reads the Camera interface's
   `IsCameraPresent` property. This does not prompt.
3. If a camera is present, the surface requests access (automatically on first
   open, or when **Allow camera** is pressed after a denial). The bridge calls
   `org.freedesktop.portal.Camera.AccessCamera` with a `handle_token`.
4. The bridge subscribes to `org.freedesktop.portal.Request.Response` on the
   returned handle. Response `0` is granted; `1` is cancelled; `2` is denied.
5. On a grant, the bridge calls `OpenPipeWireRemote` and receives the portal's
   PipeWire file descriptor. The fd is what a camera consumer should use, not
   the session's unrestricted PipeWire socket.
6. For `--request`, the bridge opens and closes the remote to prove the grant
   and exits. For `--capture`, it passes the fd to `pipewiresrc` and writes one
   PNG frame to the session runtime directory.
7. A denial or cancellation is rendered as a normal state. There is no retry
   loop. The generated test pattern remains available.

Portal call names are fixed in `config/camera/camera.conf`:
`org.freedesktop.portal.Camera` at `/org/freedesktop/portal/desktop` on the
session bus, with `org.freedesktop.portal.Request` responses.

The portal backend owns the actual prompt and the per-application permission
store. This repository does not install a polkit agent, change the portal
configuration or grant camera access to a remote session.

## Graceful states

The UI and bridge use explicit states. A missing camera, portal or frame is
never a fatal shell error.

| State | Meaning | UI behaviour |
| --- | --- | --- |
| `starting` | helper has not answered yet | status pill says starting; actions disabled |
| `ready` | portal reachable and a camera is present | permission action or capture action; no live preview claim |
| `no-camera` | portal reachable, `IsCameraPresent=false` | "No camera"; generated test pattern; no permission prompt |
| `permission-denied` | portal response code 2 | "Camera access denied"; no live capture; pattern remains |
| `permission-cancelled` | portal response code 1 | "Camera access cancelled"; no live capture; pattern remains |
| `portal-unavailable` | portal absent, stopped or unreachable | "Camera portal unavailable"; live capture disabled |
| `capture-failed` | the one-frame pipeline failed | error token shown; pattern remains |
| `unavailable` | no portal and no camera source found | "Camera unavailable"; pattern remains |
| `disabled` | `PADILHA_CAMERA_BACKEND=off` or `test-pattern` | backend disabled; generated pattern only |

`PADILHA_CAMERA_BACKEND=off` is a test/deployment hook that never starts the
helper. `PADILHA_CAMERA_BACKEND=test-pattern` is an explicit pattern-only
mode. `PADILHA_CAMERA_DEMO=1|0` overrides the shell's demo flag for screenshots
and offscreen renders. `PADILHA_CAMERA_AUTOREQUEST=0` disables the first-open
permission request.

The camera surface does not claim a live viewfinder. When a camera is ready it
shows an explanation until **Capture** writes a frame; after a successful
capture it displays that one frame. Continuous preview and recording are not
implemented.

## Test patterns

The fallback is a deterministic generated pattern, not a photo:

- `shell/components/CameraTestPattern.qml` draws colour bars, a checkerboard,
  a centre reticle and a border with the Padilha palette. It is used for the
  no-camera preview and offscreen renders.
- `scripts/camera-bridge.py --test-pattern PATH [--width W] [--height H]`
  writes the same idea as a PNG using only the Python standard library. The
  PNG contains a `tEXt` chunk saying `generated test pattern; not a photograph
  or camera image`.
- The default size is 640×480 (`CAMERA_TEST_PATTERN_WIDTH` and
  `CAMERA_TEST_PATTERN_HEIGHT`). Dimensions are validated to 64–4096.
- No generated pattern is committed. The tests create patterns in a temporary
  directory; the application creates them under
  `$XDG_RUNTIME_DIR/maria-padilha-camera`.

```sh
scripts/camera-bridge.py --test-pattern /tmp/padilha-pattern.png
python3 - <<'PY'
import struct
data = open('/tmp/padilha-pattern.png', 'rb').read()
print(data[:8], struct.unpack('>II', data[16:24]))
PY
```

## Capture and storage

`--capture` requests portal access, opens the PipeWire remote and runs one
bounded pipeline:

```
pipewiresrc fd=<portal-fd> num-buffers=1
  ! videoconvert ! pngenc ! filesink location=<session-runtime>/frame.png
```

The output path is chosen by the bridge when none is passed. The directory is
created with mode `0700` and is under `$XDG_RUNTIME_DIR`; the bridge falls back
to a private temporary directory if the runtime directory is unavailable.
Captures are not added to a gallery, indexed, uploaded or copied into the
image. A failed capture removes a zero-length partial file.

The helper accepts `--camera-node NAME` to pass a PipeWire `target-object` for
a future camera picker. The current UI does not expose camera selection.

## Privacy contract

- No photograph, screenshot, stock image or generated test image is tracked in
  this repository. `tests/camera.sh` fails if a raster image appears under the
  camera tree or anywhere in the tracked tree.
- `CAMERA_STORE_CAPTURES=false`, `CAMERA_UPLOAD_CAPTURES=false`,
  `CAMERA_LOG_IMAGE_DATA=false`, `CAMERA_LOG_CAPTURE_PATHS=false` and
  `CAMERA_BUNDLE_TEST_IMAGES=false`.
- The bridge writes image bytes only to the capture file. It never prints
  frame contents, capture paths, request tokens or remote error messages.
- Errors are stable tokens such as `portal-unavailable`, `no-camera`,
  `permission-denied`, `portal-remote-failed` or `capture-failed`.
- Camera QML contains no `console.log`, `console.warn` or `console.error`.
- The lock surface does not reveal camera state beyond the shell's normal
  status summary, and the IPC `status` call reports state names and counts,
  never image data or paths.
- The test suite uses the emulated portal and generated patterns. It does not
  open the host camera or capture the desktop.

This is a repository policy and a runtime check, not a formal audit of every
application in the guest, the portal backend or the camera firmware. A
compromised portal backend or vendor sensor driver is outside this contract.

## Test hooks

| Variable | Effect |
| --- | --- |
| `PADILHA_CAMERA_DEMO=1\|0` | force deterministic demo camera state, or force the real helper |
| `PADILHA_CAMERA_BACKEND=auto\|off\|test-pattern` | start the helper, or render the fallback without a process |
| `PADILHA_CAMERA_AUTOREQUEST=0` | do not request portal access when the surface first opens |
| `PADILHA_CAMERA_BRIDGE=/path` | override the bridge path |
| `PADILHA_SHELL_SURFACE=camera` | open the camera surface for a render or demo |
| `PADILHA_SHELL_CAMERA_SELFTEST=1` | run the fake-portal shell selftest |

The shell IPC also exposes `qs ipc call padilha-shell camera`. `status`
includes `camera`, `cameraAvailable`, `cameraPresent`, `cameraPermission`,
`cameraPreview` and `cameraFallback`, never image bytes or capture paths.

## Verification

```sh
make camera-test     # policy, generated pattern, emulated portal, no-camera, shell
make shell-test      # QML lint, selftest, camera and other surface renders
make test            # full repository gate
```

The emulated portal is a **D-Bus fixture**, not a portal backend and not a
camera. It proves the bridge's state machine, permission responses and capture
pipeline construction. It does not prove a real prompt, sensor enumeration,
libcamera tuning or hardware capture.

The manual path for a supported device or a camera-equipped guest is
[the QEMU/manual camera checklist](qemu-camera-checklist.md).

## Known limitations

1. **No real camera or photograph was tested in this checkout.** The emulated
   portal and generated pattern are the only automated results.
2. **No live preview or video recording.** The app captures one frame on
   demand. Continuous preview needs a PipeWire frame sink and a render path.
3. **No flash, focus, zoom, HDR, white balance or image processing controls.**
   libcamera controls are not exposed by this UI.
4. **No camera picker.** `--camera-node` exists in the helper but the surface
   uses PipeWire's default target.
5. **No front-camera support.** Front cameras often lack mainline drivers and
   need per-device plumbing.
6. **No audio recording or media library.** This milestone is camera capture
   only; microphone and gallery integration need separate privacy review.
7. **No device claim.** A QEMU fallback pass, with or without a passed-through
   camera, does not qualify a PinePhone or any other handset.
8. **Physical support still needs ADR 0001's gate** plus the camera-specific
   evidence in the supported-device note: mainline sensor driver, libcamera
   pipeline, PipeWire SPA plugin, portal backend and an actual frame.
9. **The helper is repository-owned glue.** It is intentionally small; a
   maintained Quickshell camera service would be preferable if one becomes
   available.
10. **The portal backend is a dependency.** A session without
    `xdg-desktop-portal` cannot grant live camera access and falls back to the
    labelled test pattern.
