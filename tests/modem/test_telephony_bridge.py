#!/usr/bin/env python3
# Integration check for the telephony bridge and the calls/SMS state model.
#
# Run under `dbus-run-session` by tests/modem.sh. It starts the emulated
# ModemManager D-Bus service from tests/modem/fake_modemmanager.py and then the
# real bridge. The emulated service is not a modem: this test proves the bridge
# and the projected state, not a real call or SMS.

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FAKE = os.path.join(ROOT, "tests", "modem", "fake_modemmanager.py")
BRIDGE = os.path.join(ROOT, "scripts", "telephony-bridge.py")

SMS_SECRET = "padilha-emulated-sms-secret-9f1d"
CALL_SECRET = "+15550100999"


class ProtocolProcess:
    def __init__(self, process: subprocess.Popen):
        self.process = process
        self.buffer = b""

    def read_json(self, timeout: float = 8.0) -> dict:
        deadline = time.monotonic() + timeout
        fd = self.process.stdout.fileno()
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError("timed out waiting for a JSON protocol line")
            ready, _, _ = select.select([fd], [], [], remaining)
            if not ready:
                raise AssertionError("timed out waiting for a JSON protocol line")
            chunk = os.read(fd, 65536)
            if not chunk:
                raise AssertionError("protocol process closed its stdout")
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        return json.loads(line.decode("utf-8"))

    def send(self, payload: dict):
        self.process.stdin.write((json.dumps(payload) + "\n").encode("utf-8"))
        self.process.stdin.flush()

    def wait_for(self, predicate, timeout: float = 8.0) -> dict:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError("timed out waiting for the expected snapshot")
            message = self.read_json(remaining)
            if message.get("type") == "error":
                raise AssertionError("bridge returned an error: " + str(message.get("code")))
            if message.get("type") == "snapshot" and predicate(message):
                return message

    def close(self, timeout: float = 5.0):
        try:
            self.process.stdin.close()
        except OSError:
            pass
        try:
            self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=timeout)


def start_fake(*args: str) -> ProtocolProcess:
    process = subprocess.Popen(
        [sys.executable, FAKE, *args],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    protocol = ProtocolProcess(process)
    ready = protocol.read_json()
    assert ready.get("type") == "ready", ready
    return protocol


def start_bridge() -> ProtocolProcess:
    process = subprocess.Popen(
        [sys.executable, BRIDGE, "--session-bus"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return ProtocolProcess(process)


def message_texts(snapshot: dict) -> list[str]:
    return [message.get("text", "") for message in snapshot.get("messages", [])]


def find_message(snapshot: dict, text: str) -> dict | None:
    for message in snapshot.get("messages", []):
        if message.get("text") == text:
            return message
    return None


def find_call(snapshot: dict, number: str) -> dict | None:
    for call in snapshot.get("calls", []):
        if call.get("number") == number:
            return call
    return None


def assert_no_secret(process: subprocess.Popen, label: str):
    try:
        stderr = process.stderr.read().decode("utf-8", "replace")
    except Exception:
        stderr = ""
    assert SMS_SECRET not in stderr, label + " wrote message content to stderr"
    assert CALL_SECRET not in stderr, label + " wrote a phone number to stderr"


def main() -> int:
    fake = start_fake()
    bridge = start_bridge()
    try:
        snapshot = bridge.wait_for(lambda item: item.get("state") == "registered")
        assert snapshot["available"] is True
        assert snapshot["backend"] == "ModemManager"
        assert len(snapshot["modems"]) == 1
        assert snapshot["modems"][0]["operatorName"] == "Padilha Test Network"
        assert snapshot["modems"][0]["capabilities"]["voice"] is True
        assert snapshot["modems"][0]["capabilities"]["messaging"] is True
        assert snapshot["calls"] == []
        assert snapshot["messages"] == []

        # Outgoing SMS through Messaging.Create + Sms.Send.
        bridge.send({"cmd": "send_sms", "number": CALL_SECRET, "text": SMS_SECRET})
        snapshot = bridge.wait_for(
            lambda item: (find_message(item, SMS_SECRET) or {}).get("state") == "sent",
            timeout=10.0,
        )
        sent = find_message(snapshot, SMS_SECRET)
        assert sent is not None
        assert sent["direction"] == "outgoing"
        assert sent["number"] == CALL_SECRET
        assert "text" in sent

        # Incoming SMS through Messaging.Added, with the same privacy checks.
        fake.send({"cmd": "incoming_sms", "number": "+15550100111", "text": SMS_SECRET + "-in"})
        snapshot = bridge.wait_for(lambda item: find_message(item, SMS_SECRET + "-in") is not None)
        incoming = find_message(snapshot, SMS_SECRET + "-in")
        assert incoming is not None
        assert incoming["direction"] == "incoming"

        # Outgoing voice call through Voice.CreateCall + Call.Start.
        bridge.send({"cmd": "dial", "number": CALL_SECRET})
        snapshot = bridge.wait_for(
            lambda item: (find_call(item, CALL_SECRET) or {}).get("state") == "active",
            timeout=10.0,
        )
        dialled = find_call(snapshot, CALL_SECRET)
        assert dialled is not None
        assert dialled["direction"] == "outgoing"
        assert dialled["stateLabel"] == "active"

        # Incoming call, answer and hang up.
        fake.send({"cmd": "incoming_call", "number": "+15550100222"})
        snapshot = bridge.wait_for(
            lambda item: (find_call(item, "+15550100222") or {}).get("state") == "ringing_in"
        )
        ringing = find_call(snapshot, "+15550100222")
        assert ringing is not None
        bridge.send({"cmd": "answer", "path": ringing["path"]})
        snapshot = bridge.wait_for(
            lambda item: (find_call(item, "+15550100222") or {}).get("state") == "active"
        )
        active = find_call(snapshot, "+15550100222")
        bridge.send({"cmd": "hangup", "path": active["path"]})
        bridge.wait_for(lambda item: find_call(item, "+15550100222") is None)

        # Delete the received SMS through Messaging.Delete.
        bridge.send({"cmd": "delete_sms", "path": incoming["path"]})
        bridge.wait_for(lambda item: find_message(item, SMS_SECRET + "-in") is None)

        # No modem is a graceful state, not an error.
        fake.send({"cmd": "remove_modem"})
        snapshot = bridge.wait_for(lambda item: item.get("state") == "no-modem")
        assert snapshot["available"] is True
        assert snapshot["modems"] == []
        assert snapshot["calls"] == []
        assert snapshot["messages"] == []

        # A stopped ModemManager is a graceful unavailable state.
        fake.send({"cmd": "quit"})
        snapshot = bridge.wait_for(lambda item: item.get("state") == "unavailable", timeout=10.0)
        assert snapshot["available"] is False
        assert snapshot["modems"] == []

        bridge.send({"cmd": "quit"})
        bridge.close()
        assert_no_secret(bridge.process, "telephony bridge")
        fake.close()
        assert_no_secret(fake.process, "fake ModemManager")
    finally:
        if bridge.process.poll() is None:
            bridge.process.kill()
        if fake.process.poll() is None:
            fake.process.kill()
    # Graceful capability states from separate emulated services.
    for flags, expected_state, expected_voice, expected_messaging in [
        (("--no-modem",), "no-modem", False, False),
        (("--locked",), "locked", False, False),
        (("--no-voice",), "registered", False, True),
        (("--no-messaging",), "registered", True, False),
    ]:
        fake_state = start_fake(*flags)
        try:
            result = subprocess.run(
                [sys.executable, BRIDGE, "--session-bus", "--once"],
                capture_output=True,
                text=True,
                timeout=10.0,
                check=False,
            )
            assert result.returncode == 0, result.stderr
            payload = json.loads(result.stdout.strip().splitlines()[-1])
            assert payload["state"] == expected_state, (flags, payload["state"])
            assert payload["capabilities"]["voice"] is expected_voice, (flags, payload["capabilities"])
            assert payload["capabilities"]["messaging"] is expected_messaging, (flags, payload["capabilities"])
            assert SMS_SECRET not in result.stderr
        finally:
            fake_state.close()

    print("ok telephony bridge emulated ModemManager flow")
    return 0


if __name__ == "__main__":
    sys.exit(main())
