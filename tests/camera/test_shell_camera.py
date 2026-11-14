#!/usr/bin/env python3
# Verify that the Quickshell camera service starts the bridge, sees the portal
# camera, requests permission and reaches the ready state. Run under
# `dbus-run-session` by tests/camera.sh; the portal is the local D-Bus fixture,
# not a camera and not a real permission prompt.

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAKE = ROOT / "tests" / "camera" / "fake_camera_portal.py"
SHELL = ROOT / "shell"


def main() -> int:
    fake = subprocess.Popen(
        [sys.executable, str(FAKE)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        ready = fake.stdout.readline().decode("utf-8", "replace").strip()
        assert json.loads(ready).get("type") == "ready", ready

        with tempfile.TemporaryDirectory(prefix="padilha-camera-shell.") as runtime:
            os.chmod(runtime, 0o700)
            env = dict(os.environ)
            env.update(
                {
                    "QT_QPA_PLATFORM": "offscreen",
                    "QSG_RHI_BACKEND": "software",
                    "XDG_RUNTIME_DIR": runtime,
                    "PADILHA_SHELL_DEMO": "0",
                    "PADILHA_SHELL_SIZE": "720x1280",
                    "PADILHA_SHELL_SURFACE": "camera",
                    "PADILHA_SHELL_CAMERA_SELFTEST": "1",
                    "PADILHA_CAMERA_DEMO": "0",
                    "PADILHA_CAMERA_BACKEND": "auto",
                    "PADILHA_CAMERA_AUTOREQUEST": "1",
                    "PADILHA_SCHEME": str(ROOT / "shell" / "palettes" / "padilha-light.json"),
                }
            )
            result = subprocess.run(
                ["quickshell", "-p", str(SHELL), "--no-color"],
                env=env,
                capture_output=True,
                text=True,
                timeout=45,
                check=False,
            )
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert "PADILHA_SHELL_CAMERA_SELFTEST_PASS" in output, output
        for forbidden in ("WARN scene", "TypeError", "Cannot assign", "iVBOR"):
            assert forbidden not in output, output
        assert "PADILHA_SHELL_CAMERA_SELFTEST_FAIL" not in output, output
    finally:
        fake.terminate()
        try:
            fake.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            fake.kill()
            fake.communicate(timeout=10)
    print("ok camera shell selftest against emulated Camera portal")
    return 0


if __name__ == "__main__":
    sys.exit(main())
