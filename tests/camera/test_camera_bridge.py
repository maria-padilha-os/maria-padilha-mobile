#!/usr/bin/env python3
# Integration and unit checks for the camera bridge.
#
# Run under `dbus-run-session` by tests/camera.sh. The portal is the emulated
# D-Bus fixture in this directory, not a real portal backend and not a camera.
# The test pattern check generates files in a temporary directory; no photo or
# fixture image is committed.

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "scripts" / "camera-bridge.py"
FAKE = ROOT / "tests" / "camera" / "fake_camera_portal.py"


class PortalProcess:
    def __init__(self, *args: str):
        self.process = subprocess.Popen(
            [sys.executable, str(FAKE), *args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        ready = self.process.stdout.readline().decode("utf-8", "replace").strip()
        assert json.loads(ready).get("type") == "ready", ready

    def close(self):
        self.process.terminate()
        try:
            self.process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.communicate(timeout=10)


def run_bridge(*args: str, timeout: float = 25.0) -> tuple[int, dict, str]:
    result = subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert lines, result.stderr
    payload = json.loads(lines[-1])
    assert isinstance(payload, dict), payload
    return result.returncode, payload, result.stderr


def test_portal_states():
    portal = PortalProcess()
    try:
        code, state, stderr = run_bridge("--state")
        assert code == 0, stderr
        assert state["type"] == "state", state
        assert state["backend"] == "libcamera-pipewire-portal", state
        assert state["portal"]["available"] is True, state
        assert state["portal"]["cameraPresent"] is True, state
        assert state["permission"] == "not-requested", state
        assert state["state"] == "ready", state
        assert state["fallback"] == "test-pattern", state
        assert state["canRequest"] is True, state
        assert "path" not in state, state

        code, granted, stderr = run_bridge("--request")
        assert code == 0, stderr
        assert granted["permission"] == "granted", granted
        assert granted["state"] == "ready", granted
        assert granted["remoteOpened"] is True, granted
        assert granted["available"] is True, granted
    finally:
        portal.close()

    portal = PortalProcess("--deny")
    try:
        code, denied, stderr = run_bridge("--request")
        assert code == 0, stderr
        assert denied["state"] == "permission-denied", denied
        assert denied["permission"] == "denied", denied
        assert denied["fallback"] == "test-pattern", denied
        assert denied["portal"]["cameraPresent"] is True, denied
    finally:
        portal.close()

    portal = PortalProcess("--no-camera")
    try:
        code, absent, stderr = run_bridge("--state")
        assert code == 0, stderr
        assert absent["state"] == "no-camera", absent
        assert absent["available"] is False, absent
        assert absent["canRequest"] is False, absent
        assert absent["fallback"] == "test-pattern", absent
    finally:
        portal.close()


def test_no_portal():
    # A nested private bus has no portal owner, which exercises the graceful
    # portal-unavailable path without touching the host session.
    result = subprocess.run(
        ["dbus-run-session", "--", sys.executable, str(BRIDGE), "--state"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert lines, result.stderr
    state = json.loads(lines[-1])
    assert state["type"] == "state", state
    assert state["portal"]["available"] is False, state
    assert state["fallback"] == "test-pattern", state
    assert state["state"] in ("unavailable", "portal-unavailable"), state


def test_test_pattern_is_generated_and_deterministic():
    with tempfile.TemporaryDirectory(prefix="padilha-camera-pattern.") as directory:
        first = os.path.join(directory, "first.png")
        second = os.path.join(directory, "second.png")
        code, payload, stderr = run_bridge(
            "--test-pattern", first, "--width", "320", "--height", "240"
        )
        assert code == 0, stderr
        assert payload["type"] == "test-pattern", payload
        assert payload["generated"] is True, payload
        assert payload["path"] == first, payload
        assert payload["width"] == 320 and payload["height"] == 240, payload
        assert os.path.getsize(first) < 1024 * 1024

        code, _, stderr = run_bridge(
            "--test-pattern", second, "--width", "320", "--height", "240"
        )
        assert code == 0, stderr
        with open(first, "rb") as handle:
            first_bytes = handle.read()
        with open(second, "rb") as handle:
            second_bytes = handle.read()
        assert first_bytes == second_bytes
        assert first_bytes[:8] == b"\x89PNG\r\n\x1a\n"
        assert b"generated test pattern" in first_bytes
        assert b"not a photograph" in first_bytes
        assert hashlib.sha256(first_bytes).hexdigest() == hashlib.sha256(second_bytes).hexdigest()


def _load_bridge_module():
    spec = importlib.util.spec_from_file_location("padilha_camera_bridge", str(BRIDGE))
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_capture_pipeline_without_hardware():
    module = _load_bridge_module()

    class FakePortal:
        def __init__(self, *_args, **_kwargs):
            pass

        def available(self):
            return True

        def camera_present(self):
            return True

        def request_access(self):
            return "granted"

        def open_remote(self):
            return os.open(os.devnull, os.O_RDONLY)

    captured_commands = []

    def fake_run(command, **kwargs):
        captured_commands.append(list(command))
        location = ""
        for item in command:
            if item.startswith("location="):
                location = item.split("=", 1)[1]
        assert location
        module.write_test_pattern(location, 64, 64)
        return subprocess.CompletedProcess(command, 0, b"", b"")

    original_portal = module.CameraPortal
    original_run = module.subprocess.run
    original_which = module.shutil.which
    module.CameraPortal = FakePortal
    module.subprocess.run = fake_run
    module.shutil.which = lambda name: "/usr/bin/gst-launch-1.0" if name == "gst-launch-1.0" else None
    try:
        with tempfile.TemporaryDirectory(prefix="padilha-camera-capture.") as directory:
            target = os.path.join(directory, "frame.png")
            args = argparse.Namespace(
                bus_type=None, timeout=5, capture=target, camera_node=""
            )
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = module.action_capture(args)
            assert code == 0, output.getvalue()
            payload = json.loads(output.getvalue().strip())
            assert payload["type"] == "capture", payload
            assert payload["ok"] is True, payload
            assert payload["path"] == target, payload
            assert payload["source"] == "camera", payload
            assert os.path.getsize(target) > 0
            assert captured_commands, "the capture pipeline was not built"
            pipeline = captured_commands[0]
            assert "pipewiresrc" in pipeline, pipeline
            assert any(item.startswith("fd=") for item in pipeline), pipeline
            assert "num-buffers=1" in pipeline, pipeline
    finally:
        module.CameraPortal = original_portal
        module.subprocess.run = original_run
        module.shutil.which = original_which


def main() -> int:
    test_test_pattern_is_generated_and_deterministic()
    test_capture_pipeline_without_hardware()
    test_portal_states()
    test_no_portal()
    # Give the last fake portal time to release the bus name before the runner
    # tears down the private session.
    time.sleep(0.1)
    print("ok camera bridge portal, no-camera, fallback and capture pipeline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
