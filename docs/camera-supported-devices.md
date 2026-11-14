# Camera supported-device note

**No physical device is supported or qualified for camera capture by this
milestone.** This note records what the stack requires, what QEMU can and
cannot prove, and the evidence needed before a device is added to the support
table.

The reference image is postmarketOS/Nura stable with Phosh on aarch64. ADR 0001
already records that the PinePhone-class camera is partial, the original
PinePhone front camera has no mainline driver, and sensor/ISP work is
device-specific. General shell and modem support does not imply camera support.

## Support table

| Target | Camera status | What is verified | Notes |
| --- | --- | --- | --- |
| `qemu-aarch64` | no camera device | no-camera state, portal absence, generated pattern | QEMU validates the fallback only; it has no camera by default |
| PinePhone-class close-to-mainline handset | not supported / not claimed | none for camera | needs mainline sensor driver, libcamera pipeline, PipeWire SPA plugin and portal backend; front camera is especially unlikely |
| USB UVC webcam in a supported guest | unverified | none for camera | may appear through PipeWire if the kernel exposes UVC; not tested or claimed |
| Android/vendor camera HAL device | out of scope | none | Android is not the base selected by ADR 0001 and no vendor HAL is shipped |

“Not supported” is not a statement that a device can never work. It means this
repository has no recorded evidence that its camera produces a frame through
the documented stack. Do not turn an unverified device into a support claim
after a single successful boot.

## What “supported” means here

A device is camera-supported in this repository only when all of the following
have been recorded on that exact device and software revision:

1. the kernel exposes the sensor and ISP through the media controller;
2. **libcamera** enumerates the camera and produces a stream (`cam -l` is a
   useful read-only first check);
3. the `pipewire-spa-libcamera` plugin publishes the camera as a PipeWire video
   node;
4. `xdg-desktop-portal` and a working backend are running in the session and
   the Camera permission prompt appears;
5. `scripts/camera-bridge.py --request` reports `permission: "granted"` and
   `remoteOpened: true`;
6. `scripts/camera-bridge.py --capture` writes and displays one frame from a
   generated target;
7. the frame is not a private photo or a desktop screenshot, and no captured
   image is committed or published;
8. suspend/resume and camera re-open do not leave a stale PipeWire node;
9. the evidence names the device, kernel, sensor, libcamera version, PipeWire
   version, portal backend and result.

Items 1–3 are device/kernel plumbing. Items 4–6 are session plumbing. Item 8
is a stability check. A QEMU result cannot satisfy any of them.

## Adding a device

1. Run [`docs/qemu-camera-checklist.md`](qemu-camera-checklist.md) on the
   device with a generated target, never a private photo.
2. Record the exact device model, kernel package/version, sensor driver,
   libcamera version, PipeWire version and portal backend.
3. Add a row to the support table with `camera` and `status` columns. Use
   **verified** only after a frame was captured and displayed.
4. Link the evidence, without attaching the captured image. A textual
   description of the generated target is enough.
5. If any step is incomplete, keep the status **not supported / not claimed**
   and record the blocking step.

## QEMU expectations

The default `qemu-aarch64` machine has no camera device. That is a feature for
this milestone: it exercises the no-camera state and proves the UI does not
crash or pretend a test pattern is a photo. Do not add a host camera
passthrough or a kernel module to the reference QEMU target just to make the
camera surface look green; that would create an unreviewed hardware dependency.

A passed-through USB camera in a disposable guest may be used for the manual
checklist, but it remains an unverified target until the evidence above is
recorded. Host-side `v4l2loopback` or similar privileged setup is outside the
scope of this checkout.

## Unsupported cases

- front cameras without a mainline driver;
- sensors whose ISP needs proprietary tuning or firmware blobs;
- Android camera HAL, camera2 or vendor camera services;
- direct `/dev/video*` access that bypasses `xdg-desktop-portal`;
- continuous preview, video recording, audio recording, flash, focus, zoom,
  HDR and image processing;
- camera access in a session without a working portal backend;
- any claim based only on a QEMU fallback or a test-pattern render.

See [`docs/camera.md`](camera.md) for the stack and privacy contract and
[ADR 0004](adr/0004-camera-and-media-capture.md) for the decision.
