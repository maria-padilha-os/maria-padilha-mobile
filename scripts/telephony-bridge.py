#!/usr/bin/env python3
# Maria Padilha Mobile telephony bridge.
#
# This is a thin, read-mostly adapter between ModemManager's documented D-Bus
# API and the Quickshell calls/SMS surfaces. ModemManager remains the modem
# stack: it owns probing, SIM state, voice calls and SMS objects. This process
# only projects those objects into newline-delimited JSON for the shell and
# forwards the few user actions the UI needs.
#
# Privacy: message text, phone numbers, SIM PIN/PUK and IMSI are never written
# to stdout except as the state the UI must display, and are never written to
# stderr or a log file. Error replies carry a D-Bus error name, never the
# remote message (which may echo a number or message text).
#
# The bridge is deliberately not a daemon: it exits when stdin closes, so the
# shell controls its lifetime and no telephony process is left behind.

from __future__ import annotations

import argparse
import json
import os
import sys

try:
    import gi

    gi.require_version("Gio", "2.0")
    gi.require_version("GLib", "2.0")
    from gi.repository import Gio, GLib
except Exception:  # pragma: no cover - reported as a clean startup error
    sys.stderr.write("telephony bridge: Gio/GLib introspection is unavailable\n")
    sys.exit(2)


MM_NAME = "org.freedesktop.ModemManager1"
MM_PATH = "/org/freedesktop/ModemManager1"
OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
PROPERTIES = "org.freedesktop.DBus.Properties"

MODEM_IFACE = "org.freedesktop.ModemManager1.Modem"
MODEM_3GPP_IFACE = "org.freedesktop.ModemManager1.Modem.Modem3gpp"
VOICE_IFACE = "org.freedesktop.ModemManager1.Modem.Voice"
MESSAGING_IFACE = "org.freedesktop.ModemManager1.Modem.Messaging"
CALL_IFACE = "org.freedesktop.ModemManager1.Call"
SMS_IFACE = "org.freedesktop.ModemManager1.Sms"
SIM_IFACE = "org.freedesktop.ModemManager1.Sim"

MODEM_STATES = {
    -1: "failed",
    0: "unknown",
    1: "initializing",
    2: "locked",
    3: "disabled",
    4: "disabling",
    5: "enabling",
    6: "enabled",
    7: "searching",
    8: "registered",
    9: "disconnecting",
    10: "connecting",
    11: "connected",
}

CALL_STATES = {
    0: "unknown",
    1: "dialing",
    2: "ringing_out",
    3: "ringing_in",
    4: "active",
    5: "held",
    6: "waiting",
    7: "terminated",
}

CALL_DIRECTIONS = {0: "unknown", 1: "incoming", 2: "outgoing"}

SMS_STATES = {
    0: "unknown",
    1: "stored",
    2: "receiving",
    3: "received",
    4: "sending",
    5: "sent",
}

SMS_PDU_TYPES = {
    0: "unknown",
    1: "deliver",
    2: "submit",
    3: "status-report",
    32: "cdma-deliver",
    33: "cdma-submit",
    34: "cdma-cancellation",
    35: "cdma-delivery-acknowledgement",
    36: "cdma-user-acknowledgement",
    37: "cdma-read-acknowledgement",
}


class BridgeError(Exception):
    """An error with a token safe to show in the UI and to keep in a log."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _ifaces(managed: dict, path: str) -> dict:
    return managed.get(path, {})


def _props(ifaces: dict, interface: str) -> dict:
    return ifaces.get(interface, {}) or {}


def _prop(ifaces: dict, interface: str, name: str, default=None):
    return _props(ifaces, interface).get(name, default)


def _text(value, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


def _mapping_label(mapping: dict, value, default: str) -> str:
    try:
        key = int(value)
    except (TypeError, ValueError):
        return default
    return mapping.get(key, default)


def _redacted_error_name(error: GLib.Error) -> str:
    name = Gio.DBusError.get_remote_error(error)
    if name:
        return str(name)
    return "org.freedesktop.DBus.Error.Failed"


def _variant(value) -> GLib.Variant:
    if isinstance(value, GLib.Variant):
        return value
    if isinstance(value, bool):
        return GLib.Variant("b", value)
    if isinstance(value, int):
        return GLib.Variant("u", value)
    return GLib.Variant("s", str(value))


class TelephonyBridge:
    def __init__(self, bus_type: Gio.BusType, timeout_ms: int = 5000):
        self.timeout_ms = timeout_ms
        self.bus = Gio.bus_get_sync(bus_type, None)
        self._refresh_source = 0
        self._stdin_buffer = b""
        self._stdin_source = 0
        self._watch_id = 0
        self._loop = GLib.MainLoop()

        self.bus.signal_subscribe(
            MM_NAME,
            None,
            None,
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            self._on_dbus_signal,
        )
        self._watch_id = Gio.bus_watch_name_on_connection(
            self.bus,
            MM_NAME,
            Gio.BusNameWatcherFlags.NONE,
            self._on_name_appeared,
            self._on_name_vanished,
        )

    # ---------------------------------------------------------------- lifecycle

    def run(self) -> int:
        self._stdin_source = GLib.io_add_watch(
            sys.stdin.fileno(),
            GLib.PRIORITY_DEFAULT,
            GLib.IOCondition.IN | GLib.IOCondition.HUP,
            self._on_stdin,
        )
        GLib.idle_add(self._initial_refresh)
        self._loop.run()
        if self._refresh_source:
            GLib.source_remove(self._refresh_source)
            self._refresh_source = 0
        if self._stdin_source:
            GLib.source_remove(self._stdin_source)
            self._stdin_source = 0
        if self._watch_id:
            Gio.bus_unwatch_name(self._watch_id)
            self._watch_id = 0
        return 0

    def _initial_refresh(self):
        self._emit_snapshot()
        return GLib.SOURCE_REMOVE

    def _on_name_appeared(self, _connection, _name, _owner):
        self._schedule_refresh()

    def _on_name_vanished(self, _connection, _name):
        self._emit_unavailable()

    def _on_dbus_signal(self, _connection, _sender, _path, _interface, _member, _params):
        self._schedule_refresh()

    def _schedule_refresh(self, delay_ms: int = 60):
        if self._refresh_source:
            GLib.source_remove(self._refresh_source)
        self._refresh_source = GLib.timeout_add(delay_ms, self._refresh_from_timer)

    def _refresh_from_timer(self):
        self._refresh_source = 0
        self._emit_snapshot()
        return GLib.SOURCE_REMOVE

    # ---------------------------------------------------------------- commands

    def _on_stdin(self, fd, condition):
        if condition & GLib.IOCondition.HUP:
            self._quit()
            return GLib.SOURCE_REMOVE
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            self._quit()
            return GLib.SOURCE_REMOVE
        if not chunk:
            self._quit()
            return GLib.SOURCE_REMOVE
        self._stdin_buffer += chunk
        while b"\n" in self._stdin_buffer:
            raw, self._stdin_buffer = self._stdin_buffer.split(b"\n", 1)
            line = raw.strip()
            if line:
                self._handle_command_bytes(line)
        return GLib.SOURCE_CONTINUE

    def _quit(self):
        self._loop.quit()

    def _handle_command_bytes(self, raw: bytes):
        try:
            payload = json.loads(raw.decode("utf-8", "replace"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._emit_error("bad-command", "")
            return
        if not isinstance(payload, dict):
            self._emit_error("bad-command", "")
            return
        command = _text(payload.get("cmd"))
        try:
            self._handle_command(command, payload)
        except BridgeError as error:
            self._emit_error(error.code, command)
        except GLib.Error as error:
            self._emit_error(_redacted_error_name(error), command)
        except (TypeError, ValueError):
            self._emit_error("bad-command", command)
        except Exception:
            # Never print the exception text: it can contain message content or
            # a phone number from a malformed D-Bus reply.
            self._emit_error("internal-error", command)

    def _handle_command(self, command: str, payload: dict):
        if command == "refresh":
            self._emit_snapshot()
        elif command == "dial":
            self._dial(payload)
        elif command == "answer":
            self._answer(payload)
        elif command == "hangup":
            self._hangup(payload)
        elif command == "hangup_all":
            self._voice_method("HangupAll", None)
            self._after_command()
        elif command == "send_dtmf":
            self._send_dtmf(payload)
        elif command == "send_sms":
            self._send_sms(payload)
        elif command == "delete_sms":
            self._delete_sms(payload)
        elif command == "quit":
            self._quit()
        else:
            raise BridgeError("unknown-command")

    def _after_command(self):
        self._schedule_refresh(120)

    def _dbus(self, path: str, interface: str, method: str, params=None, reply_type=None):
        try:
            return self.bus.call_sync(
                MM_NAME,
                path,
                interface,
                method,
                params,
                reply_type,
                Gio.DBusCallFlags.NONE,
                self.timeout_ms,
                None,
            )
        except GLib.Error as error:
            raise BridgeError(_redacted_error_name(error))

    def _modem_path(self, need_interface: str | None = None) -> str:
        managed = self._managed_objects()
        for path, ifaces in managed.items():
            if MODEM_IFACE not in ifaces:
                continue
            if need_interface is None or need_interface in ifaces:
                return path
        if need_interface == VOICE_IFACE:
            raise BridgeError("no-voice")
        if need_interface == MESSAGING_IFACE:
            raise BridgeError("no-messaging")
        raise BridgeError("no-modem")

    def _managed_objects(self) -> dict:
        reply = self._dbus(MM_PATH, OBJECT_MANAGER, "GetManagedObjects", None, GLib.VariantType.new("(a{oa{sa{sv}}})"))
        unpacked = reply.unpack()
        return unpacked[0] if unpacked else {}

    def _call_path(self, payload: dict, preferred_states: set[str]) -> str:
        requested = _text(payload.get("path"))
        if requested:
            return requested
        managed = self._managed_objects()
        fallback = ""
        for path, ifaces in managed.items():
            if CALL_IFACE not in ifaces:
                continue
            state = _mapping_label(CALL_STATES, _prop(ifaces, CALL_IFACE, "State", 0), "unknown")
            if state in preferred_states:
                return path
            if not fallback:
                fallback = path
        if fallback:
            return fallback
        raise BridgeError("no-call")

    def _dial(self, payload: dict):
        number = _text(payload.get("number")).strip()
        if not number:
            raise BridgeError("empty-number")
        modem = self._modem_path(VOICE_IFACE)
        properties = {"Number": GLib.Variant("s", number)}
        reply = self._dbus(
            modem,
            VOICE_IFACE,
            "CreateCall",
            GLib.Variant("(a{sv})", (properties,)),
            GLib.VariantType.new("(o)"),
        )
        call_path = reply.unpack()[0]
        # ModemManager creates an outgoing call in UNKNOWN; Start moves it to
        # DIALING. Some modems may have started it already, so a failed Start is
        # not treated as fatal if the call object exists.
        try:
            self._dbus(call_path, CALL_IFACE, "Start", None, None)
        except BridgeError:
            pass
        self._after_command()

    def _answer(self, payload: dict):
        path = self._call_path(payload, {"ringing_in", "waiting"})
        self._dbus(path, CALL_IFACE, "Accept", None, None)
        self._after_command()

    def _hangup(self, payload: dict):
        path = self._call_path(payload, {"active", "held", "dialing", "ringing_out", "ringing_in", "waiting"})
        try:
            self._dbus(path, CALL_IFACE, "Hangup", None, None)
        except BridgeError:
            # A call can terminate between the snapshot and the action. Fall
            # back to the modem-wide hangup so the UI still clears the call.
            self._voice_method("HangupAll", None)
        self._after_command()

    def _send_dtmf(self, payload: dict):
        digit = _text(payload.get("digit"))
        if digit not in "0123456789ABCD*#abcd" or len(digit) != 1:
            raise BridgeError("bad-dtmf")
        path = self._call_path(payload, {"active"})
        self._dbus(path, CALL_IFACE, "SendDtmf", GLib.Variant("(s)", (digit,)), None)
        self._after_command()

    def _voice_method(self, method: str, params):
        modem = self._modem_path(VOICE_IFACE)
        self._dbus(modem, VOICE_IFACE, method, params, None)

    def _send_sms(self, payload: dict):
        number = _text(payload.get("number")).strip()
        text = _text(payload.get("text"))
        if not number:
            raise BridgeError("empty-number")
        if not text:
            raise BridgeError("empty-message")
        modem = self._modem_path(MESSAGING_IFACE)
        properties = {
            "Number": GLib.Variant("s", number),
            "Text": GLib.Variant("s", text),
        }
        reply = self._dbus(
            modem,
            MESSAGING_IFACE,
            "Create",
            GLib.Variant("(a{sv})", (properties,)),
            GLib.VariantType.new("(o)"),
        )
        sms_path = reply.unpack()[0]
        self._dbus(sms_path, SMS_IFACE, "Send", None, None)
        self._after_command()

    def _delete_sms(self, payload: dict):
        path = _text(payload.get("path"))
        if not path:
            raise BridgeError("missing-path")
        modem = self._modem_path(MESSAGING_IFACE)
        self._dbus(modem, MESSAGING_IFACE, "Delete", GLib.Variant("(o)", (path,)), None)
        self._after_command()

    # ----------------------------------------------------------------- project

    def _emit_unavailable(self):
        self._emit(
            {
                "type": "snapshot",
                "schema": 1,
                "backend": "ModemManager",
                "available": False,
                "state": "unavailable",
                "modems": [],
                "calls": [],
                "messages": [],
                "capabilities": {"voice": False, "messaging": False},
            }
        )

    def _emit_error(self, code: str, command: str):
        self._emit({"type": "error", "code": code, "command": command})

    @staticmethod
    def _emit(payload: dict):
        sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()

    def _emit_snapshot(self):
        try:
            managed = self._managed_objects()
        except BridgeError:
            self._emit_unavailable()
            return
        snapshot = self._project(managed)
        self._emit(snapshot)

    def _project(self, managed: dict) -> dict:
        modems = []
        modem_paths = []
        calls = []
        messages = []

        for path, ifaces in managed.items():
            if MODEM_IFACE in ifaces:
                modem_paths.append(path)
                modems.append(self._project_modem(path, ifaces, managed))
            if CALL_IFACE in ifaces:
                calls.append(self._project_call(path, ifaces))
            if SMS_IFACE in ifaces:
                messages.append(self._project_sms(path, ifaces))

        calls.sort(key=lambda item: item["path"])
        messages.sort(key=lambda item: (item.get("timestamp") or "", item["path"]))
        modems.sort(key=lambda item: item["path"])

        if not modem_paths:
            state = "no-modem"
            capabilities = {"voice": False, "messaging": False}
        else:
            primary = modems[0]
            state = primary["state"]
            capabilities = primary["capabilities"]

        return {
            "type": "snapshot",
            "schema": 1,
            "backend": "ModemManager",
            "available": True,
            "state": state,
            "modems": modems,
            "calls": calls,
            "messages": messages,
            "capabilities": capabilities,
        }

    def _project_modem(self, path: str, ifaces: dict, managed: dict) -> dict:
        state = _mapping_label(MODEM_STATES, _prop(ifaces, MODEM_IFACE, "State", 0), "unknown")
        signal_value = _prop(ifaces, MODEM_IFACE, "SignalQuality", (-1, False))
        if isinstance(signal_value, (list, tuple)) and signal_value:
            try:
                quality = int(signal_value[0])
            except (TypeError, ValueError):
                quality = -1
        else:
            quality = -1
        if quality == 99:
            quality = -1

        operator = _text(_prop(ifaces, MODEM_3GPP_IFACE, "OperatorName", ""))
        if not operator:
            sim_path = _text(_prop(ifaces, MODEM_IFACE, "Sim", ""))
            if sim_path:
                operator = _text(_prop(_ifaces(managed, sim_path), SIM_IFACE, "OperatorName", ""))
        registration = _prop(ifaces, MODEM_3GPP_IFACE, "RegistrationState", 0)
        unlock_required = _prop(ifaces, MODEM_IFACE, "UnlockRequired", 0)
        voice = VOICE_IFACE in ifaces
        messaging = MESSAGING_IFACE in ifaces
        emergency_only = bool(_prop(ifaces, VOICE_IFACE, "EmergencyOnly", False))

        return {
            "path": path,
            "manufacturer": _text(_prop(ifaces, MODEM_IFACE, "Manufacturer", "")),
            "model": _text(_prop(ifaces, MODEM_IFACE, "Model", "")),
            "state": state,
            "stateLabel": state,
            "failedReason": _prop(ifaces, MODEM_IFACE, "StateFailedReason", 0),
            "unlockRequired": bool(unlock_required),
            "registrationState": registration,
            "operatorName": operator,
            "signalQuality": quality,
            "simPresent": bool(_prop(ifaces, MODEM_IFACE, "Sim", "")),
            "capabilities": {"voice": voice, "messaging": messaging},
            "voice": voice,
            "messaging": messaging,
            "emergencyOnly": emergency_only,
        }

    def _project_call(self, path: str, ifaces: dict) -> dict:
        state = _mapping_label(CALL_STATES, _prop(ifaces, CALL_IFACE, "State", 0), "unknown")
        direction = _mapping_label(CALL_DIRECTIONS, _prop(ifaces, CALL_IFACE, "Direction", 0), "unknown")
        return {
            "path": path,
            "state": state,
            "stateLabel": state,
            "direction": direction,
            "directionLabel": direction,
            "number": _text(_prop(ifaces, CALL_IFACE, "Number", "")),
            "multiparty": bool(_prop(ifaces, CALL_IFACE, "Multiparty", False)),
            "audioPort": _text(_prop(ifaces, CALL_IFACE, "AudioPort", "")),
        }

    def _project_sms(self, path: str, ifaces: dict) -> dict:
        state = _mapping_label(SMS_STATES, _prop(ifaces, SMS_IFACE, "State", 0), "unknown")
        pdu_type = _mapping_label(SMS_PDU_TYPES, _prop(ifaces, SMS_IFACE, "PduType", 0), "unknown")
        text = _text(_prop(ifaces, SMS_IFACE, "Text", ""))
        if not text and _prop(ifaces, SMS_IFACE, "Data", None):
            text = "[binary message]"
        direction = "incoming" if pdu_type in {"deliver", "cdma-deliver"} else "outgoing"
        return {
            "path": path,
            "state": state,
            "stateLabel": state,
            "pduType": pdu_type,
            "direction": direction,
            "number": _text(_prop(ifaces, SMS_IFACE, "Number", "")),
            "text": text,
            "timestamp": _text(_prop(ifaces, SMS_IFACE, "Timestamp", "")),
            "deliveryState": _prop(ifaces, SMS_IFACE, "DeliveryState", 0),
        }


def once(bus_type: Gio.BusType, timeout_ms: int) -> int:
    bridge = TelephonyBridge(bus_type, timeout_ms)
    try:
        managed = bridge._managed_objects()
    except BridgeError:
        bridge._emit_unavailable()
        return 0
    bridge._emit(bridge._project(managed))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="ModemManager to Quickshell telephony bridge")
    parser.add_argument("--session-bus", action="store_true", help="use the session bus (test/emulation only)")
    parser.add_argument("--once", action="store_true", help="emit one snapshot and exit")
    parser.add_argument("--timeout", type=int, default=5000, help="D-Bus call timeout in milliseconds")
    args = parser.parse_args()

    bus_type = Gio.BusType.SESSION if args.session_bus else Gio.BusType.SYSTEM
    if args.once:
        return once(bus_type, args.timeout)
    return TelephonyBridge(bus_type, args.timeout).run()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
    except GLib.Error:
        sys.stderr.write("telephony bridge: cannot connect to the requested D-Bus\n")
        sys.exit(2)
