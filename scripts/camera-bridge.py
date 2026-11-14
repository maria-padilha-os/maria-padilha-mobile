#!/usr/bin/env python3
# Maria Padilha Mobile camera bridge.
#
# This helper is the only camera process the Padilha shell starts. It is not a
# camera daemon and it does not touch /dev/video*: libcamera owns sensor and
# ISP enumeration, PipeWire carries the buffers, and xdg-desktop-portal is the
# permission boundary. Each invocation performs one action and exits:
#
#   --state        report portal/PipeWire/libcamera availability (no prompt)
#   --request      ask the portal for camera access, then open/close a remote
#   --capture      request access and capture one PipeWire frame to a PNG
#   --test-pattern generate a deterministic test pattern, no camera involved
#
# Output is one newline-delimited JSON object on stdout. Errors are tokens, not
# remote messages. Image bytes, frame contents, capture paths and portal
# request tokens are never written to stderr or a log.

from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

try:
    import gi

    gi.require_version("Gio", "2.0")
    gi.require_version("GLib", "2.0")
    from gi.repository import Gio, GLib
except Exception:  # pragma: no cover - test patterns still work without Gio
    Gio = None
    GLib = None


SCHEMA = 1
BACKEND = "libcamera-pipewire-portal"
PORTAL_NAME = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
CAMERA_IFACE = "org.freedesktop.portal.Camera"
REQUEST_IFACE = "org.freedesktop.portal.Request"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"
DBUS_NAME = "org.freedesktop.DBus"
DBUS_PATH = "/org/freedesktop/DBus"
DBUS_IFACE = "org.freedesktop.DBus"

# Portal Request::Response codes.
RESPONSE_SUCCESS = 0
RESPONSE_CANCELLED = 1
RESPONSE_OTHER = 2

# PipeWire media classes that expose a camera source. The exact class can vary
# with the libcamera SPA version; all variants are treated as video sources.
CAMERA_MEDIA_CLASSES = {
    "Video/Source",
    "Video/Capture",
    "Video/Source/Stream",
    "Video/Device",
}


class CameraError(Exception):
    """A camera failure with a stable token that is safe to log and display."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def _base_payload(kind: str) -> dict:
    return {
        "type": kind,
        "schema": SCHEMA,
        "backend": BACKEND,
        "timestamp": int(time.time()),
    }


def _error_payload(code: str) -> dict:
    payload = _base_payload("error")
    payload["code"] = code
    payload["ok"] = False
    return payload


# --------------------------------------------------------------------- portal


class CameraPortal:
    """Minimal client for org.freedesktop.portal.Camera on the session bus."""

    def __init__(self, bus_type, timeout_s: int = 5):
        if Gio is None or GLib is None:
            raise CameraError("gio-unavailable")
        self.timeout_ms = max(1, timeout_s) * 1000
        self.bus = Gio.bus_get_sync(bus_type, None)

    def available(self) -> bool:
        try:
            result = self.bus.call_sync(
                DBUS_NAME,
                DBUS_PATH,
                DBUS_IFACE,
                "NameHasOwner",
                GLib.Variant("(s)", (PORTAL_NAME,)),
                GLib.VariantType.new("(b)"),
                Gio.DBusCallFlags.NONE,
                self.timeout_ms,
                None,
            )
            return bool(result.unpack()[0])
        except Exception:
            return False

    def camera_present(self) -> bool:
        try:
            result = self.bus.call_sync(
                PORTAL_NAME,
                PORTAL_PATH,
                PROPERTIES_IFACE,
                "Get",
                GLib.Variant("(ss)", (CAMERA_IFACE, "IsCameraPresent")),
                GLib.VariantType.new("(v)"),
                Gio.DBusCallFlags.NONE,
                self.timeout_ms,
                None,
            )
            return bool(result.unpack()[0])
        except Exception as exc:
            raise CameraError("portal-unavailable") from exc

    def request_access(self) -> str:
        """Request camera access and return the portal response token.

        A granted request returns ``granted``. A denied/cancelled request is a
        normal permission state, not a crash, and is reported by the caller.
        """
        token = "padilha_camera_%d_%d" % (os.getpid(), int(time.time() * 1000))
        responses: dict[str, tuple[int, dict]] = {}
        pending = {"handle": ""}
        loop = GLib.MainLoop()
        source = 0

        def on_response(_conn, _sender, path, _iface, _member, params):
            try:
                code, results = params.unpack()
            except Exception:
                return
            message_path = str(path)
            responses[message_path] = (int(code), results or {})
            # An unrelated Request can share the interface; only wake for the
            # handle returned by our AccessCamera call once it is known.
            if not pending["handle"] or message_path == pending["handle"]:
                loop.quit()

        subscription = self.bus.signal_subscribe(
            PORTAL_NAME,
            REQUEST_IFACE,
            "Response",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            on_response,
        )

        try:
            options = {"handle_token": GLib.Variant("s", token)}
            result = self.bus.call_sync(
                PORTAL_NAME,
                PORTAL_PATH,
                CAMERA_IFACE,
                "AccessCamera",
                GLib.Variant("(a{sv})", (options,)),
                GLib.VariantType.new("(o)"),
                Gio.DBusCallFlags.NONE,
                self.timeout_ms,
                None,
            )
            handle = str(result.unpack()[0])
            pending["handle"] = handle
        except Exception as exc:
            self.bus.signal_unsubscribe(subscription)
            raise CameraError("portal-error") from exc

        # The response may already have arrived while call_sync was running.
        if handle not in responses:
            def on_timeout():
                loop.quit()
                return False

            source = GLib.timeout_add(self.timeout_ms, on_timeout)
            loop.run()
            if source:
                GLib.source_remove(source)
                source = 0
        self.bus.signal_unsubscribe(subscription)

        if handle not in responses:
            raise CameraError("portal-timeout")
        code, _results = responses[handle]
        if code == RESPONSE_SUCCESS:
            return "granted"
        if code == RESPONSE_CANCELLED:
            return "cancelled"
        return "denied"

    def open_remote(self):
        """Open the portal PipeWire remote and return its file descriptor."""
        try:
            result, fd_list = self.bus.call_with_unix_fd_list_sync(
                PORTAL_NAME,
                PORTAL_PATH,
                CAMERA_IFACE,
                "OpenPipeWireRemote",
                GLib.Variant("(a{sv})", ({},)),
                GLib.VariantType.new("(h)"),
                Gio.DBusCallFlags.NONE,
                self.timeout_ms,
                None,
                None,
            )
            index = int(result.unpack()[0])
            fd = fd_list.get(index)
        except Exception as exc:
            raise CameraError("portal-remote-failed") from exc
        if fd is None or fd < 0:
            raise CameraError("portal-remote-failed")
        try:
            os.set_inheritable(fd, True)
        except OSError:
            pass
        return fd


# ----------------------------------------------------------------- detection


def _run_quiet(command: list[str], timeout_s: float = 3.0):
    try:
        return subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            timeout=timeout_s,
            text=True,
        )
    except (OSError, subprocess.SubprocessError):
        return None


def pipewire_cameras() -> dict:
    """Return camera nodes from pw-dump without probing device nodes."""
    result = _run_quiet(["pw-dump"])
    if result is None or result.returncode != 0:
        return {"available": False, "cameras": []}
    try:
        objects = json.loads(result.stdout)
    except (TypeError, ValueError):
        return {"available": False, "cameras": []}

    cameras = []
    for obj in objects:
        if not isinstance(obj, dict):
            continue
        props = (obj.get("info") or {}).get("props") or {}
        media_class = str(props.get("media.class") or "")
        if media_class not in CAMERA_MEDIA_CLASSES:
            continue
        cameras.append(
            {
                "id": obj.get("id", 0),
                "name": str(props.get("node.name") or ""),
                "description": str(props.get("node.description") or ""),
                "mediaClass": media_class,
            }
        )
    return {"available": True, "cameras": cameras}


def libcamera_cameras() -> dict:
    """Return the camera list from libcamera's optional `cam -l` tool."""
    cam = shutil.which("cam")
    if not cam:
        return {"available": False, "cameras": []}
    result = _run_quiet([cam, "-l"])
    if result is None or result.returncode != 0:
        return {"available": True, "cameras": []}

    cameras = []
    current = None
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("-"):
            if current:
                cameras.append(current)
            current = {"name": line[1:].strip(), "detail": ""}
        elif current is not None:
            current["detail"] = (current["detail"] + " " + line).strip()
    if current:
        cameras.append(current)
    return {"available": True, "cameras": cameras}


def _state_payload(portal_available: bool, camera_present: bool, permission: str,
                   pipewire: dict, libcamera: dict, error: str = "") -> dict:
    payload = _base_payload("state")
    camera_count = max(len(pipewire.get("cameras", [])),
                       len(libcamera.get("cameras", [])))
    if portal_available:
        portal_state = "available"
    else:
        portal_state = "unavailable"

    # Availability means a portal-gated, permission-ready camera. A camera
    # visible only through direct PipeWire or libcamera is reported for
    # diagnostics but is not treated as usable because the permission boundary
    # is the portal.
    available = bool(portal_available and camera_present)
    if portal_available and camera_present:
        if permission in ("denied", "permission-denied"):
            state = "permission-denied"
        elif permission in ("cancelled", "permission-cancelled"):
            state = "permission-cancelled"
        else:
            state = "ready"
    elif portal_available and not camera_present:
        state = "no-camera"
    elif camera_count > 0:
        state = "portal-unavailable"
    else:
        state = "unavailable"

    payload.update(
        {
            "ok": state not in ("unavailable",),
            "available": available,
            "state": state,
            "permission": permission,
            "canRequest": bool(portal_available and camera_present),
            "fallback": "test-pattern",
            "cameraCount": camera_count,
            "portal": {
                "available": bool(portal_available),
                "state": portal_state,
                "name": PORTAL_NAME,
                "cameraPresent": bool(camera_present),
            },
            "pipewire": pipewire,
            "libcamera": libcamera,
        }
    )
    if error:
        payload["error"] = error
    return payload


def gather_state(portal: CameraPortal | None, permission: str = "not-requested",
                 error: str = "") -> dict:
    pipewire = pipewire_cameras()
    libcamera = libcamera_cameras()
    portal_available = bool(portal and portal.available())
    camera_present = False
    if portal_available:
        try:
            camera_present = portal.camera_present()
        except CameraError:
            portal_available = False
            error = error or "portal-unavailable"
    return _state_payload(
        portal_available,
        camera_present,
        permission,
        pipewire,
        libcamera,
        error=error,
    )


# --------------------------------------------------------------- test pattern


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def _pattern_row(width: int, y: int, height: int) -> bytes:
    # Upper 60%: seven vertical colour bars. Lower 40%: a checkerboard with a
    # centre crosshair. The pattern is deterministic and contains no photo.
    bars = [
        (235, 235, 235),
        (235, 235, 32),
        (32, 235, 235),
        (32, 235, 32),
        (235, 32, 235),
        (235, 32, 32),
        (32, 32, 235),
    ]
    row = bytearray()
    split = int(height * 0.60)
    for x in range(width):
        if y < split:
            index = min(len(bars) - 1, (x * len(bars)) // max(1, width))
            row.extend(bars[index])
        else:
            size = max(8, min(width, height) // 16)
            cell = ((x // size) + (y // size)) % 2
            value = 38 if cell == 0 else 176
            row.extend((value, value, value))
    # Border and centre reticle make the image obviously synthetic.
    if y < 4 or y >= height - 4:
        row = bytearray()
        for _ in range(width):
            row.extend((24, 24, 24))
    else:
        for x in range(width):
            if x < 4 or x >= width - 4:
                row[x * 3 : x * 3 + 3] = bytes((24, 24, 24))
    mid_y = height // 2
    mid_x = width // 2
    if abs(y - mid_y) <= 2:
        for x in range(max(0, mid_x - width // 8),
                       min(width, mid_x + width // 8)):
            row[x * 3 : x * 3 + 3] = bytes((255, 255, 255))
    return bytes(row)


def write_test_pattern(path: str, width: int, height: int) -> dict:
    if width < 64 or height < 64 or width > 4096 or height > 4096:
        raise CameraError("invalid-test-pattern-size")

    directory = os.path.dirname(os.path.abspath(path))
    if directory:
        os.makedirs(directory, mode=0o700, exist_ok=True)

    rows = bytearray()
    for y in range(height):
        rows.extend(b"\x00")
        rows.extend(_pattern_row(width, y, height))
    # Vertical centre reticle for every row.
    for y in range(height):
        offset = y * (width * 3 + 1) + 1
        for x in range(max(0, width // 2 - 2), min(width, width // 2 + 2)):
            rows[offset + x * 3 : offset + x * 3 + 3] = bytes((255, 255, 255))

    png = b"\x89PNG\r\n\x1a\n"
    png += _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += _png_chunk(b"tEXt", b"Software\x00maria-padilha-camera-test-pattern")
    png += _png_chunk(
        b"tEXt", b"Comment\x00generated test pattern; not a photograph or camera image"
    )
    png += _png_chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += _png_chunk(b"IEND", b"")

    with open(path, "wb") as handle:
        handle.write(png)
    return {
        "ok": True,
        "path": path,
        "generated": True,
        "width": width,
        "height": height,
    }


def _private_capture_path(suffix: str = ".png") -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    directory = os.path.join(runtime, "maria-padilha-camera")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, path = tempfile.mkstemp(prefix="capture-", suffix=suffix, dir=directory)
    os.close(fd)
    return path


# -------------------------------------------------------------------- actions


def action_state(args) -> int:
    try:
        portal = CameraPortal(args.bus_type, args.timeout) if Gio is not None else None
    except CameraError as exc:
        emit(gather_state(None, error=exc.code))
        return 0
    except Exception:
        emit(gather_state(None, error="portal-unavailable"))
        return 0
    emit(gather_state(portal))
    return 0


def _authorize(portal: CameraPortal) -> int:
    if not portal.available():
        raise CameraError("portal-unavailable")
    if not portal.camera_present():
        raise CameraError("no-camera")
    result = portal.request_access()
    if result == "cancelled":
        raise CameraError("permission-cancelled")
    if result != "granted":
        raise CameraError("permission-denied")
    return portal.open_remote()


def action_request(args) -> int:
    portal = None
    try:
        portal = CameraPortal(args.bus_type, args.timeout)
        state = gather_state(portal)
        if not state["portal"]["available"]:
            emit(state)
            return 0
        if not state["portal"]["cameraPresent"]:
            emit(state)
            return 0
        fd = _authorize(portal)
        try:
            state = gather_state(portal, permission="granted")
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
        state["remoteOpened"] = True
        emit(state)
        return 0
    except CameraError as exc:
        permission = "denied" if exc.code == "permission-denied" else (
            "cancelled" if exc.code == "permission-cancelled" else "not-requested")
        state = gather_state(portal, permission=permission, error=exc.code)
        emit(state)
        return 0 if exc.code in ("permission-denied", "permission-cancelled") else 1
    except Exception:
        emit(gather_state(portal, error="portal-unavailable"))
        return 1


def _frame_size(path: str) -> tuple[int, int]:
    try:
        with open(path, "rb") as handle:
            header = handle.read(24)
        if header[:8] != b"\x89PNG\r\n\x1a\n":
            return (0, 0)
        width, height = struct.unpack(">II", header[16:24])
        return (int(width), int(height))
    except OSError:
        return (0, 0)


def action_capture(args) -> int:
    fd = -1
    path = args.capture or _private_capture_path()
    try:
        portal = CameraPortal(args.bus_type, args.timeout)
        fd = _authorize(portal)
        gst = shutil.which("gst-launch-1.0")
        if not gst:
            raise CameraError("capture-unavailable")
        pipeline = [
            gst,
            "-q",
            "-e",
            "pipewiresrc",
            "fd=%d" % fd,
            "num-buffers=1",
            "client-name=maria-padilha-camera",
        ]
        if args.camera_node:
            pipeline.append("target-object=%s" % args.camera_node)
        pipeline += [
            "!",
            "videoconvert",
            "!",
            "pngenc",
            "!",
            "filesink",
            "location=%s" % path,
        ]
        result = subprocess.run(
            pipeline,
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=max(5, args.timeout + 10),
            pass_fds=(fd,),
        )
        if result.returncode != 0 or not os.path.exists(path) or os.path.getsize(path) == 0:
            raise CameraError("capture-failed")
        width, height = _frame_size(path)
        payload = _base_payload("capture")
        payload.update(
            {
                "ok": True,
                "path": path,
                "source": "camera",
                "permission": "granted",
                "width": width,
                "height": height,
            }
        )
        emit(payload)
        return 0
    except CameraError as exc:
        try:
            if os.path.exists(path) and os.path.getsize(path) == 0:
                os.unlink(path)
        except OSError:
            pass
        emit(_error_payload(exc.code))
        return 1
    except Exception:
        try:
            if os.path.exists(path) and os.path.getsize(path) == 0:
                os.unlink(path)
        except OSError:
            pass
        emit(_error_payload("capture-failed"))
        return 1
    finally:
        if fd >= 0:
            try:
                os.close(fd)
            except OSError:
                pass


def action_test_pattern(args) -> int:
    path = args.test_pattern or _private_capture_path()
    try:
        result = write_test_pattern(path, args.width, args.height)
    except CameraError as exc:
        emit(_error_payload(exc.code))
        return 1
    except OSError:
        emit(_error_payload("test-pattern-write-failed"))
        return 1
    payload = _base_payload("test-pattern")
    payload.update(result)
    emit(payload)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Maria Padilha camera state, portal permission and capture helper",
    )
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--state", action="store_true",
                        help="report portal/PipeWire/libcamera state (default)")
    action.add_argument("--request", action="store_true",
                        help="request portal camera access and verify the remote")
    action.add_argument("--capture", nargs="?", const="", metavar="PATH",
                        help="capture one frame; a private runtime path is used if omitted")
    action.add_argument("--test-pattern", nargs="?", const="", metavar="PATH",
                        help="write a generated test pattern; no camera is used")
    parser.add_argument("--bus", choices=("session", "system"), default="session",
                        help="D-Bus used for the portal (default: session)")
    parser.add_argument("--session-bus", dest="bus", action="store_const",
                        const="session", help="use the session bus (the portal default)")
    parser.add_argument("--system-bus", dest="bus", action="store_const",
                        const="system", help="use the system bus (tests only)")
    parser.add_argument("--timeout", type=int, default=5,
                        help="portal/PipeWire timeout in seconds (default: 5)")
    parser.add_argument("--width", type=int, default=640,
                        help="test-pattern width (default: 640)")
    parser.add_argument("--height", type=int, default=480,
                        help="test-pattern height (default: 480)")
    parser.add_argument("--camera-node", default="",
                        help="optional PipeWire target-object name for capture")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.bus_type = None
    if Gio is not None:
        args.bus_type = Gio.BusType.SESSION if args.bus == "session" else Gio.BusType.SYSTEM
    try:
        if args.test_pattern is not None:
            return action_test_pattern(args)
        if args.capture is not None:
            return action_capture(args)
        if args.request:
            return action_request(args)
        return action_state(args)
    except KeyboardInterrupt:
        return 130
    except Exception:
        # Never print a traceback: it can contain a path or a portal message.
        emit(_error_payload("internal-error"))
        return 1


if __name__ == "__main__":
    sys.exit(main())
