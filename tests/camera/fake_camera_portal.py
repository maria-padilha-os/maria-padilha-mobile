#!/usr/bin/env python3
# Emulated xdg-desktop-portal Camera service for the unprivileged camera tests.
#
# This is a D-Bus fixture, not a camera and not a real portal backend. It
# exposes the published org.freedesktop.portal.Camera surface so the bridge's
# permission and no-camera paths can be exercised without a portal prompt or a
# physical device. It returns a memfd from OpenPipeWireRemote, never frames.

from __future__ import annotations

import argparse
import os
import sys
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)

try:
    import gi

    gi.require_version("Gio", "2.0")
    gi.require_version("GLib", "2.0")
    from gi.repository import Gio, GLib
except Exception:
    sys.stderr.write("fake camera portal: Gio/GLib introspection is unavailable\n")
    sys.exit(2)


PORTAL_NAME = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
CAMERA_IFACE = "org.freedesktop.portal.Camera"

CAMERA_XML = """
<node>
  <interface name="org.freedesktop.portal.Camera">
    <method name="AccessCamera">
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="OpenPipeWireRemote">
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="h" name="fd" direction="out"/>
    </method>
    <property name="IsCameraPresent" type="b" access="read"/>
    <property name="version" type="u" access="read"/>
  </interface>
</node>
"""


class FakePortal:
    def __init__(self, camera_present: bool, deny: bool, cancel: bool):
        self.camera_present = camera_present
        self.deny = deny
        self.cancel = cancel
        self.connection = None
        self._fd = -1

    def on_bus_acquired(self, connection, _name):
        self.connection = connection
        info = Gio.DBusNodeInfo.new_for_xml(CAMERA_XML)
        connection.register_object(
            PORTAL_PATH,
            info.interfaces[0],
            self.on_method_call,
            self.on_get_property,
            None,
        )
        payload = (
            '{"type":"ready","service":"%s","cameraPresent":%s}'
            % (PORTAL_NAME, "true" if self.camera_present else "false")
        )
        print(payload, flush=True)

    def on_method_call(self, connection, sender, _path, _iface, method, params, invocation):
        if method == "AccessCamera":
            self._access_camera(connection, sender, params, invocation)
            return
        if method == "OpenPipeWireRemote":
            self._open_remote(invocation)
            return
        invocation.return_dbus_error(
            "org.freedesktop.DBus.Error.UnknownMethod", "unsupported method"
        )

    def _access_camera(self, connection, sender, params, invocation):
        try:
            options = params.unpack()[0]
        except Exception:
            options = {}
        token = str(options.get("handle_token") or "padilha_camera_test")
        owner = sender[1:].replace(".", "_") if sender.startswith(":") else "test"
        handle = "%s/request/%s/%s" % (PORTAL_PATH, owner, token)
        if self.deny:
            code = 1 if self.cancel else 2
        else:
            code = 0

        def respond():
            if self.connection is not None:
                self.connection.emit_signal(
                    sender,
                    handle,
                    "org.freedesktop.portal.Request",
                    "Response",
                    GLib.Variant("(ua{sv})", (code, {})),
                )
            return False

        GLib.idle_add(respond)
        invocation.return_value(GLib.Variant("(o)", (handle,)))

    def _open_remote(self, invocation):
        if self._fd < 0:
            try:
                self._fd = os.memfd_create("padilha-fake-camera-portal")
            except (AttributeError, OSError):
                self._fd = os.open(os.devnull, os.O_RDONLY)
        fds = Gio.UnixFDList.new()
        index = fds.append(self._fd)
        invocation.return_value_with_unix_fd_list(GLib.Variant("(h)", (index,)), fds)

    def on_get_property(self, _connection, _sender, _path, _iface, name):
        if name == "IsCameraPresent":
            return GLib.Variant("b", self.camera_present)
        if name == "version":
            return GLib.Variant("u", 1)
        return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="emulated Camera portal fixture")
    parser.add_argument("--camera-present", action="store_true", default=True,
                        help="advertise a camera (default)")
    parser.add_argument("--no-camera", dest="camera_present", action="store_false",
                        help="advertise no camera")
    parser.add_argument("--deny", action="store_true",
                        help="return a denied AccessCamera response")
    parser.add_argument("--cancel", action="store_true",
                        help="return a cancelled AccessCamera response")
    args = parser.parse_args(argv)

    portal = FakePortal(args.camera_present, args.deny, args.cancel)
    Gio.bus_own_name(
        Gio.BusType.SESSION,
        PORTAL_NAME,
        Gio.BusNameOwnerFlags.NONE,
        portal.on_bus_acquired,
        None,
        None,
    )
    GLib.MainLoop().run()
    if portal._fd >= 0:
        os.close(portal._fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
