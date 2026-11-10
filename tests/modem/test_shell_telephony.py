#!/usr/bin/env python3
# Verify that the Quickshell telephony service starts the bridge, consumes its
# first snapshot and reaches the registered/capable state. Run under
# `dbus-run-session` by tests/modem.sh; the ModemManager service is the local
# D-Bus fixture, not a real modem.

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAKE = ROOT / "tests" / "modem" / "fake_modemmanager.py"
SHELL = ROOT / "shell"


def main() -> int:
    fake = subprocess.Popen(
        [sys.executable, str(FAKE)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        ready = fake.stdout.readline().decode("utf-8", "replace").strip()
        assert json.loads(ready).get("type") == "ready", ready

        with tempfile.TemporaryDirectory(prefix="padilha-telephony-shell.") as runtime:
            os.chmod(runtime, 0o700)
            env = dict(os.environ)
            env.update(
                {
                    "QT_QPA_PLATFORM": "offscreen",
                    "QSG_RHI_BACKEND": "software",
                    "XDG_RUNTIME_DIR": runtime,
                    "PADILHA_SHELL_DEMO": "0",
                    "PADILHA_SHELL_SIZE": "720x1280",
                    "PADILHA_SHELL_SURFACE": "calls",
                    "PADILHA_SHELL_TELEPHONY_SELFTEST": "1",
                    "PADILHA_TELEPHONY_DEMO": "0",
                    "PADILHA_TELEPHONY_BUS": "session",
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
        assert "PADILHA_SHELL_TELEPHONY_SELFTEST_PASS" in output, output
        for forbidden in ("WARN scene", "TypeError", "Cannot assign"):
            assert forbidden not in output, output
        assert "PADILHA_SHELL_TELEPHONY_SELFTEST_FAIL" not in output, output
    finally:
        fake.terminate()
        try:
            fake.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            fake.kill()
    print("ok telephony shell selftest against emulated ModemManager")
    return 0


if __name__ == "__main__":
    sys.exit(main())
