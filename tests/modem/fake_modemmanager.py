#!/usr/bin/env python3
# ModemManager D-Bus fixture for the Maria Padilha telephony checks.
#
# This is an emulated ModemManager service, not a modem and not a real
# call/SMS test. It exports the subset of the ModemManager 1.x D-Bus API that
# the telephony bridge uses: ObjectManager, Modem, Modem3gpp, Voice, Messaging,
# Call, Sms and Sim. It is modelled on upstream ModemManager's
# `tools/test-modemmanager-service.py` approach, but extended with Voice and
# Messaging so the calls/SMS UI has a stateful counterpart.
#
# The service listens on the session bus and accepts newline-delimited JSON
# control commands on stdin. It never prints message text, phone numbers or
# credentials: only `{"type":"ready"}` and command acknowledgements.

from __future__ import annotations

import argparse
import json
import os
import sys
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)

try:
    import gi

    gi.require_version("Gio", "2.0")
    gi.require_version("GLib", "2.0")
    from gi.repository import Gio, GLib
except Exception:  # pragma: no cover - reported as a clean startup error
    sys.stderr.write("fake ModemManager: Gio/GLib introspection is unavailable\n")
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

MANAGER_XML = """
<node>
  <interface name="org.freedesktop.ModemManager1">
    <method name="ScanDevices"/>
    <method name="SetLogging"><arg name="level" type="s" direction="in"/></method>
    <method name="ReportKernelEvent"><arg name="properties" type="a{sv}" direction="in"/></method>
    <method name="InhibitDevice"><arg name="uid" type="s" direction="in"/><arg name="inhibit" type="b" direction="in"/></method>
    <property name="Version" type="s" access="read"/>
  </interface>
  <interface name="org.freedesktop.DBus.ObjectManager">
    <method name="GetManagedObjects">
      <arg name="object_paths_interfaces_and_properties" type="a{oa{sa{sv}}}" direction="out"/>
    </method>
    <signal name="InterfacesAdded">
      <arg name="object_path" type="o"/>
      <arg name="interfaces_and_properties" type="a{sa{sv}}"/>
    </signal>
    <signal name="InterfacesRemoved">
      <arg name="object_path" type="o"/>
      <arg name="interfaces" type="as"/>
    </signal>
  </interface>
</node>
"""

MODEM_XML = """
<node>
  <interface name="org.freedesktop.ModemManager1.Modem">
    <method name="Enable"><arg name="enable" type="b" direction="in"/></method>
    <method name="ListBearers"><arg name="bearers" type="ao" direction="out"/></method>
    <property name="Sim" type="o" access="read"/>
    <property name="SimSlots" type="ao" access="read"/>
    <property name="PrimarySimSlot" type="u" access="read"/>
    <property name="State" type="i" access="read"/>
    <property name="StateFailedReason" type="u" access="read"/>
    <property name="UnlockRequired" type="u" access="read"/>
    <property name="SignalQuality" type="(ub)" access="read"/>
    <property name="Manufacturer" type="s" access="read"/>
    <property name="Model" type="s" access="read"/>
    <property name="Revision" type="s" access="read"/>
    <property name="Device" type="s" access="read"/>
    <property name="Drivers" type="as" access="read"/>
    <property name="Plugin" type="s" access="read"/>
    <property name="PrimaryPort" type="s" access="read"/>
    <property name="PowerState" type="u" access="read"/>
    <property name="SupportedCapabilities" type="au" access="read"/>
    <property name="CurrentCapabilities" type="u" access="read"/>
  </interface>
  <interface name="org.freedesktop.ModemManager1.Modem.Modem3gpp">
    <property name="Imei" type="s" access="read"/>
    <property name="RegistrationState" type="u" access="read"/>
    <property name="OperatorCode" type="s" access="read"/>
    <property name="OperatorName" type="s" access="read"/>
  </interface>
  <interface name="org.freedesktop.ModemManager1.Modem.Voice">
    <method name="ListCalls"><arg name="result" type="ao" direction="out"/></method>
    <method name="DeleteCall"><arg name="path" type="o" direction="in"/></method>
    <method name="CreateCall">
      <arg name="properties" type="a{sv}" direction="in"/>
      <arg name="path" type="o" direction="out"/>
    </method>
    <method name="HangupAll"/>
    <signal name="CallAdded"><arg name="path" type="o"/></signal>
    <signal name="CallDeleted"><arg name="path" type="o"/></signal>
    <property name="Calls" type="ao" access="read"/>
    <property name="EmergencyOnly" type="b" access="read"/>
  </interface>
  <interface name="org.freedesktop.ModemManager1.Modem.Messaging">
    <method name="List"><arg name="result" type="ao" direction="out"/></method>
    <method name="Delete"><arg name="path" type="o" direction="in"/></method>
    <method name="Create">
      <arg name="properties" type="a{sv}" direction="in"/>
      <arg name="path" type="o" direction="out"/>
    </method>
    <signal name="Added"><arg name="path" type="o"/><arg name="received" type="b"/></signal>
    <signal name="Deleted"><arg name="path" type="o"/></signal>
    <property name="Messages" type="ao" access="read"/>
    <property name="SupportedStorages" type="au" access="read"/>
    <property name="DefaultStorage" type="u" access="read"/>
  </interface>
</node>
"""

CALL_XML = """
<node>
  <interface name="org.freedesktop.ModemManager1.Call">
    <method name="Start"/>
    <method name="Accept"/>
    <method name="Hangup"/>
    <method name="SendDtmf"><arg name="dtmf" type="s" direction="in"/></method>
    <signal name="StateChanged"><arg name="old" type="i"/><arg name="new" type="i"/><arg name="reason" type="u"/></signal>
    <property name="State" type="i" access="read"/>
    <property name="StateReason" type="i" access="read"/>
    <property name="Direction" type="i" access="read"/>
    <property name="Number" type="s" access="read"/>
    <property name="Multiparty" type="b" access="read"/>
    <property name="AudioPort" type="s" access="read"/>
    <property name="AudioFormat" type="a{sv}" access="read"/>
  </interface>
</node>
"""

SMS_XML = """
<node>
  <interface name="org.freedesktop.ModemManager1.Sms">
    <method name="Send"/>
    <method name="Store"><arg name="storage" type="u" direction="in"/></method>
    <property name="State" type="u" access="read"/>
    <property name="PduType" type="u" access="read"/>
    <property name="Number" type="s" access="read"/>
    <property name="Text" type="s" access="read"/>
    <property name="Data" type="ay" access="read"/>
    <property name="SMSC" type="s" access="read"/>
    <property name="Class" type="i" access="read"/>
    <property name="Timestamp" type="s" access="read"/>
    <property name="DeliveryState" type="u" access="read"/>
    <property name="Storage" type="u" access="read"/>
  </interface>
</node>
"""

SIM_XML = """
<node>
  <interface name="org.freedesktop.ModemManager1.Sim">
    <method name="SendPin"><arg name="pin" type="s" direction="in"/></method>
    <method name="SendPuk"><arg name="puk" type="s" direction="in"/><arg name="pin" type="s" direction="in"/></method>
    <property name="Active" type="b" access="read"/>
    <property name="SimIdentifier" type="s" access="read"/>
    <property name="Imsi" type="s" access="read"/>
    <property name="OperatorIdentifier" type="s" access="read"/>
    <property name="OperatorName" type="s" access="read"/>
    <property name="EmergencyNumbers" type="as" access="read"/>
  </interface>
</node>
"""


def vstr(value: str) -> GLib.Variant:
    return GLib.Variant("s", str(value))


def vint(value: int) -> GLib.Variant:
    return GLib.Variant("i", int(value))


def vuint(value: int) -> GLib.Variant:
    return GLib.Variant("u", int(value))


def vbool(value: bool) -> GLib.Variant:
    return GLib.Variant("b", bool(value))


def vpaths(paths) -> GLib.Variant:
    return GLib.Variant("ao", list(paths))


def vastrings(values) -> GLib.Variant:
    return GLib.Variant("as", list(values))


def _native(value):
    if isinstance(value, GLib.Variant):
        return value.unpack()
    return value


class Entry:
    def __init__(self, path: str, xml: str, props: dict):
        self.path = path
        self.xml = xml
        self.props = props
        self.ids = []


class FakeModemManager:
    def __init__(self):
        self.connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.loop = GLib.MainLoop()
        self.entries: dict[str, Entry] = {}
        self.modem_path = f"{MM_PATH}/Modem/0"
        self.sim_path = f"{MM_PATH}/SIM/0"
        self.call_counter = 0
        self.sms_counter = 0
        self.voice_available = True
        self.messaging_available = True
        self._stdin_buffer = b""
        self._stdin_source = 0

        self._acquire_name()
        self._register_entry(self._manager_entry())
        self._add_modem()

        self._stdin_source = GLib.io_add_watch(
            sys.stdin.fileno(),
            GLib.PRIORITY_DEFAULT,
            GLib.IOCondition.IN | GLib.IOCondition.HUP,
            self._on_stdin,
        )

    # ---------------------------------------------------------------- lifecycle

    def _acquire_name(self):
        reply = self.connection.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "RequestName",
            GLib.Variant("(su)", (MM_NAME, 0)),
            GLib.VariantType.new("(u)"),
            Gio.DBusCallFlags.NONE,
            5000,
            None,
        )
        result = reply.unpack()[0]
        if result not in (1, 4):
            sys.stderr.write("fake ModemManager: cannot own the session bus name\n")
            sys.exit(1)

    def run(self):
        self._emit_control({"type": "ready"})
        try:
            self.loop.run()
        finally:
            if self._stdin_source:
                GLib.source_remove(self._stdin_source)
                self._stdin_source = 0
        return 0

    def _quit(self):
        self.loop.quit()

    def _on_stdin(self, fd, condition):
        if condition & GLib.IOCondition.HUP:
            self._stdin_source = 0
            self._quit()
            return GLib.SOURCE_REMOVE
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            self._stdin_source = 0
            self._quit()
            return GLib.SOURCE_REMOVE
        if not chunk:
            self._stdin_source = 0
            self._quit()
            return GLib.SOURCE_REMOVE
        self._stdin_buffer += chunk
        while b"\n" in self._stdin_buffer:
            raw, self._stdin_buffer = self._stdin_buffer.split(b"\n", 1)
            line = raw.strip()
            if line:
                self._handle_control(line)
        return GLib.SOURCE_CONTINUE

    @staticmethod
    def _emit_control(payload: dict):
        sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
        sys.stdout.flush()

    def _handle_control(self, raw: bytes):
        try:
            payload = json.loads(raw.decode("utf-8", "replace"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._emit_control({"type": "error", "code": "bad-command"})
            return
        command = str(payload.get("cmd", ""))
        try:
            if command == "incoming_call":
                self._incoming_call(str(payload.get("number", "")))
            elif command == "incoming_sms":
                self._incoming_sms(str(payload.get("number", "")), str(payload.get("text", "")))
            elif command == "remove_modem":
                self._remove_modem()
            elif command == "set_modem_state":
                self._set_modem_state(int(payload.get("state", 8)))
            elif command == "remove_call":
                self._remove_call(str(payload.get("path", "")))
            elif command == "remove_sms":
                self._remove_sms(str(payload.get("path", "")))
            elif command == "quit":
                self._quit()
                return
            else:
                self._emit_control({"type": "error", "code": "unknown-command"})
                return
        except (TypeError, ValueError):
            self._emit_control({"type": "error", "code": "bad-command"})
            return
        self._emit_control({"type": "ok", "cmd": command})

    # ------------------------------------------------------------ registration

    def _manager_entry(self) -> Entry:
        return Entry(
            MM_PATH,
            MANAGER_XML,
            {"org.freedesktop.ModemManager1": {"Version": vstr("1.24.2-emulated")}},
        )

    def _register_entry(self, entry: Entry):
        node = Gio.DBusNodeInfo.new_for_xml(entry.xml)
        for interface in node.interfaces:
            entry.ids.append(
                self.connection.register_object(
                    entry.path,
                    interface,
                    self._method_call,
                    self._get_property,
                    self._set_property,
                )
            )
        self.entries[entry.path] = entry

    def _unregister_entry(self, entry: Entry):
        for object_id in entry.ids:
            self.connection.unregister_object(object_id)
        entry.ids = []
        self.entries.pop(entry.path, None)

    def _get_property(self, _connection, _sender, path, interface, name, _user_data):
        entry = self.entries.get(path)
        if entry is None:
            return None
        value = entry.props.get(interface, {}).get(name)
        if value is None:
            return None
        return value

    def _set_property(self, _connection, _sender, _path, _interface, _name, _value, _user_data):
        return False

    def _method_call(self, _connection, _sender, path, interface, method, params, invocation):
        entry = self.entries.get(path)
        if entry is None:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownObject", "unknown object")
            return
        try:
            result = self._dispatch(entry, interface, method, params)
        except (TypeError, ValueError, KeyError):
            invocation.return_dbus_error("org.freedesktop.ModemManager1.Error.Core.Failed", "emulated call failed")
            return
        if result is None:
            invocation.return_value(None)
        else:
            invocation.return_value(result)

    def _dispatch(self, entry: Entry, interface: str, method: str, params):
        if interface == OBJECT_MANAGER and method == "GetManagedObjects":
            return GLib.Variant("(a{oa{sa{sv}}})", (self._managed_objects(),))
        if interface == "org.freedesktop.ModemManager1":
            return None
        if interface == MODEM_IFACE:
            return self._modem_method(entry, method, params)
        if interface == MODEM_3GPP_IFACE:
            return None
        if interface == VOICE_IFACE:
            return self._voice_method(entry, method, params)
        if interface == MESSAGING_IFACE:
            return self._messaging_method(entry, method, params)
        if interface == CALL_IFACE:
            return self._call_method(entry, method, params)
        if interface == SMS_IFACE:
            return self._sms_method(entry, method, params)
        if interface == SIM_IFACE:
            return None
        return None

    # ---------------------------------------------------------------- projection

    def _managed_objects(self) -> dict:
        managed = {}
        for path, entry in self.entries.items():
            if path == MM_PATH:
                continue
            managed[path] = {interface: dict(props) for interface, props in entry.props.items()}
        return managed

    def _emit_properties(self, path: str, interface: str, changed: dict):
        self.connection.emit_signal(
            None,
            path,
            PROPERTIES,
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (interface, changed, [])),
        )

    def _emit_interfaces_added(self, entry: Entry):
        self.connection.emit_signal(
            None,
            MM_PATH,
            OBJECT_MANAGER,
            "InterfacesAdded",
            GLib.Variant("(oa{sa{sv}})", (entry.path, {interface: dict(props) for interface, props in entry.props.items()})),
        )

    def _emit_interfaces_removed(self, path: str, interfaces):
        self.connection.emit_signal(
            None,
            MM_PATH,
            OBJECT_MANAGER,
            "InterfacesRemoved",
            GLib.Variant("(oas)", (path, list(interfaces))),
        )

    # --------------------------------------------------------------- modem setup

    def _add_modem(self, state: int = 8, locked: bool = False):
        self._remove_modem(quiet=True)
        sim = Entry(
            self.sim_path,
            SIM_XML,
            {
                SIM_IFACE: {
                    "Active": vbool(True),
                    "SimIdentifier": vstr("89860000000000000000"),
                    "Imsi": vstr("001010000000000"),
                    "OperatorIdentifier": vstr("00101"),
                    "OperatorName": vstr("Padilha Test Network"),
                    "EmergencyNumbers": vastrings(["112"]),
                }
            },
        )
        modem_props = {
            MODEM_IFACE: {
                "Sim": GLib.Variant("o", self.sim_path),
                "SimSlots": GLib.Variant("ao", [self.sim_path]),
                "PrimarySimSlot": vuint(1),
                "State": vint(state),
                "StateFailedReason": vuint(0),
                "UnlockRequired": vuint(1 if locked else 0),
                "SignalQuality": GLib.Variant("(ub)", (72, False)),
                "Manufacturer": vstr("Padilha"),
                "Model": vstr("Emulated modem"),
                "Revision": vstr("test"),
                "Device": vstr("/dev/emulated"),
                "Drivers": vastrings(["emulated"]),
                "Plugin": vstr("emulated"),
                "PrimaryPort": vstr("emulated0"),
                "PowerState": vuint(3),
                "SupportedCapabilities": GLib.Variant("au", [0x1F]),
                "CurrentCapabilities": vuint(0x1F),
            },
            MODEM_3GPP_IFACE: {
                "Imei": vstr("000000000000000"),
                "RegistrationState": vuint(1 if state >= 8 else 2),
                "OperatorCode": vstr("00101"),
                "OperatorName": vstr("Padilha Test Network"),
            },
        }
        if self.voice_available and state >= 6:
            modem_props[VOICE_IFACE] = {
                "Calls": vpaths([]),
                "EmergencyOnly": vbool(False),
            }
        if self.messaging_available and state >= 6:
            modem_props[MESSAGING_IFACE] = {
                "Messages": vpaths([]),
                "SupportedStorages": GLib.Variant("au", [1, 2]),
                "DefaultStorage": vuint(1),
            }
        modem = Entry(self.modem_path, MODEM_XML, modem_props)
        self._register_entry(sim)
        self._register_entry(modem)
        self._emit_interfaces_added(sim)
        self._emit_interfaces_added(modem)

    def _remove_modem(self, quiet: bool = False):
        for path in list(self.entries):
            if path == MM_PATH:
                continue
            entry = self.entries[path]
            interfaces = list(entry.props)
            self._unregister_entry(entry)
            if not quiet:
                self._emit_interfaces_removed(path, interfaces)
        self.call_counter = 0
        self.sms_counter = 0

    def _modem_method(self, entry: Entry, method: str, _params):
        if method == "Enable":
            return None
        if method == "ListBearers":
            return GLib.Variant("(ao)", ([],))
        return None

    def _set_modem_state(self, state: int):
        modem = self.entries.get(self.modem_path)
        if modem is None or MODEM_IFACE not in modem.props:
            return
        modem.props[MODEM_IFACE]["State"] = vint(state)
        self._emit_properties(self.modem_path, MODEM_IFACE, {"State": vint(state)})
        if MODEM_3GPP_IFACE in modem.props:
            registration = 1 if state >= 8 else 2
            modem.props[MODEM_3GPP_IFACE]["RegistrationState"] = vuint(registration)
            self._emit_properties(self.modem_path, MODEM_3GPP_IFACE, {"RegistrationState": vuint(registration)})

    # ------------------------------------------------------------------- voice

    def _voice_method(self, entry: Entry, method: str, params):
        if method == "ListCalls":
            return GLib.Variant("(ao)", (self._call_paths(),))
        if method == "CreateCall":
            properties = params.unpack()[0]
            number = str(_native(properties.get("Number", "")))
            call = self._add_call(number, 2, 0)
            return GLib.Variant("(o)", (call.path,))
        if method == "DeleteCall":
            path = params.unpack()[0]
            self._remove_call(path)
            return None
        if method == "HangupAll":
            for path in list(self._call_paths()):
                self._remove_call(path)
            return None
        return None

    def _call_paths(self):
        modem = self.entries.get(self.modem_path)
        if modem is None or VOICE_IFACE not in modem.props:
            return []
        return list(modem.props[VOICE_IFACE]["Calls"].unpack())

    def _add_call(self, number: str, direction: int, state: int):
        self.call_counter += 1
        path = f"{MM_PATH}/Call/{self.call_counter}"
        props = {
            CALL_IFACE: {
                "State": vint(state),
                "StateReason": vint(0),
                "Direction": vint(direction),
                "Number": vstr(number),
                "Multiparty": vbool(False),
                "AudioPort": vstr(""),
                "AudioFormat": GLib.Variant("a{sv}", {}),
            }
        }
        call = Entry(path, CALL_XML, props)
        self._register_entry(call)
        self._update_call_list()
        self._emit_interfaces_added(call)
        self.connection.emit_signal(None, self.modem_path, VOICE_IFACE, "CallAdded", GLib.Variant("(o)", (path,)))
        return call

    def _update_call_list(self):
        modem = self.entries.get(self.modem_path)
        if modem is None or VOICE_IFACE not in modem.props:
            return
        paths = [path for path, entry in self.entries.items() if CALL_IFACE in entry.props]
        modem.props[VOICE_IFACE]["Calls"] = vpaths(paths)
        self._emit_properties(self.modem_path, VOICE_IFACE, {"Calls": vpaths(paths)})

    def _remove_call(self, path: str):
        entry = self.entries.get(path)
        if entry is None or CALL_IFACE not in entry.props:
            return
        self._unregister_entry(entry)
        self._update_call_list()
        self._emit_interfaces_removed(path, [CALL_IFACE])
        self.connection.emit_signal(None, self.modem_path, VOICE_IFACE, "CallDeleted", GLib.Variant("(o)", (path,)))

    def _call_method(self, entry: Entry, method: str, _params):
        state = int(entry.props[CALL_IFACE]["State"].unpack())
        if method == "Start":
            self._set_call_state(entry, 1, 1)
            GLib.timeout_add(250, self._activate_call, entry.path)
        elif method == "Accept":
            self._set_call_state(entry, 4, 3)
        elif method == "Hangup":
            self._set_call_state(entry, 7, 4)
            GLib.timeout_add(250, self._remove_call, entry.path)
        elif method == "SendDtmf":
            return None
        elif method == "Deflect":
            return None
        return None

    def _set_call_state(self, entry: Entry, state: int, reason: int):
        old = int(entry.props[CALL_IFACE]["State"].unpack())
        entry.props[CALL_IFACE]["State"] = vint(state)
        entry.props[CALL_IFACE]["StateReason"] = vint(reason)
        self._emit_properties(entry.path, CALL_IFACE, {"State": vint(state), "StateReason": vint(reason)})
        self.connection.emit_signal(
            None,
            entry.path,
            CALL_IFACE,
            "StateChanged",
            GLib.Variant("(iiu)", (old, state, reason)),
        )

    def _activate_call(self, path: str):
        entry = self.entries.get(path)
        if entry is not None and int(entry.props[CALL_IFACE]["State"].unpack()) in (1, 2):
            self._set_call_state(entry, 4, 3)
        return GLib.SOURCE_REMOVE

    def _incoming_call(self, number: str):
        self._add_call(number, 1, 3)

    # ------------------------------------------------------------------- SMS

    def _messaging_method(self, entry: Entry, method: str, params):
        if method == "List":
            return GLib.Variant("(ao)", (self._sms_paths(),))
        if method == "Create":
            properties = params.unpack()[0]
            number = str(_native(properties.get("Number", "")))
            text = str(_native(properties.get("Text", "")))
            sms = self._add_sms(number, text, 2, 1)
            return GLib.Variant("(o)", (sms.path,))
        if method == "Delete":
            path = params.unpack()[0]
            self._remove_sms(path)
            return None
        return None

    def _sms_paths(self):
        modem = self.entries.get(self.modem_path)
        if modem is None or MESSAGING_IFACE not in modem.props:
            return []
        return list(modem.props[MESSAGING_IFACE]["Messages"].unpack())

    def _add_sms(self, number: str, text: str, pdu_type: int, state: int):
        self.sms_counter += 1
        path = f"{MM_PATH}/SMS/{self.sms_counter}"
        props = {
            SMS_IFACE: {
                "State": vuint(state),
                "PduType": vuint(pdu_type),
                "Number": vstr(number),
                "Text": vstr(text),
                "Data": GLib.Variant("ay", b""),
                "SMSC": vstr("+15550199"),
                "Class": vint(-1),
                "Timestamp": vstr("2026-11-10T10:25:08+00:00"),
                "DeliveryState": vuint(0),
                "Storage": vuint(1),
            }
        }
        sms = Entry(path, SMS_XML, props)
        self._register_entry(sms)
        self._update_sms_list()
        self._emit_interfaces_added(sms)
        received = pdu_type in (1, 32)
        self.connection.emit_signal(None, self.modem_path, MESSAGING_IFACE, "Added", GLib.Variant("(ob)", (path, received)))
        return sms

    def _update_sms_list(self):
        modem = self.entries.get(self.modem_path)
        if modem is None or MESSAGING_IFACE not in modem.props:
            return
        paths = [path for path, entry in self.entries.items() if SMS_IFACE in entry.props]
        modem.props[MESSAGING_IFACE]["Messages"] = vpaths(paths)
        self._emit_properties(self.modem_path, MESSAGING_IFACE, {"Messages": vpaths(paths)})

    def _remove_sms(self, path: str):
        entry = self.entries.get(path)
        if entry is None or SMS_IFACE not in entry.props:
            return
        self._unregister_entry(entry)
        self._update_sms_list()
        self._emit_interfaces_removed(path, [SMS_IFACE])
        self.connection.emit_signal(None, self.modem_path, MESSAGING_IFACE, "Deleted", GLib.Variant("(o)", (path,)))

    def _sms_method(self, entry: Entry, method: str, _params):
        if method == "Send":
            self._set_sms_state(entry, 4)
            GLib.timeout_add(250, self._mark_sms_sent, entry.path)
        return None

    def _set_sms_state(self, entry: Entry, state: int):
        entry.props[SMS_IFACE]["State"] = vuint(state)
        self._emit_properties(entry.path, SMS_IFACE, {"State": vuint(state)})

    def _mark_sms_sent(self, path: str):
        entry = self.entries.get(path)
        if entry is not None and int(entry.props[SMS_IFACE]["State"].unpack()) == 4:
            self._set_sms_state(entry, 5)
        return GLib.SOURCE_REMOVE

    def _incoming_sms(self, number: str, text: str):
        self._add_sms(number, text, 1, 3)


def main() -> int:
    parser = argparse.ArgumentParser(description="Emulated ModemManager session service")
    parser.add_argument("--no-modem", action="store_true", help="start with no modem object")
    parser.add_argument("--locked", action="store_true", help="modem is SIM-locked and has no voice/messaging interfaces")
    parser.add_argument("--no-voice", action="store_true", help="do not export the Voice interface")
    parser.add_argument("--no-messaging", action="store_true", help="do not export the Messaging interface")
    args = parser.parse_args()

    service = FakeModemManager()
    service.voice_available = not args.no_voice
    service.messaging_available = not args.no_messaging
    if args.no_modem:
        service._remove_modem(quiet=True)
    else:
        service._add_modem(state=2 if args.locked else 8, locked=args.locked)
    return service.run()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
    except GLib.Error:
        sys.stderr.write("fake ModemManager: cannot connect to the session bus\n")
        sys.exit(2)
