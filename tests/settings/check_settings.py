#!/usr/bin/env python3
"""Static and persisted-config checks for the mobile settings surface.

The static half proves the pages exist and that the settings code uses the
existing Padilha config keys without shelling out to privileged or destructive
network tools. The optional --config half validates the JSON that the
navigation/persistence self-test wrote.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PAGES = {
    "network": "NetworkSettingsPage.qml",
    "display": "DisplaySettingsPage.qml",
    "sound": "SoundSettingsPage.qml",
    "battery": "BatterySettingsPage.qml",
    "language": "LanguageSettingsPage.qml",
    "about": "AboutSettingsPage.qml",
}

REQUIRED_FILES = [
    "shell/surfaces/SettingsSurface.qml",
    "shell/components/SettingsStore.qml",
    "shell/settings/SettingsPage.qml",
    "shell/settings/SettingsSection.qml",
    "shell/settings/SettingsRowCard.qml",
    "shell/settings/SettingsToggleRow.qml",
    "shell/settings/SettingsSliderRow.qml",
    "shell/settings/SettingsSelectRow.qml",
    "shell/settings/SettingsInfoRow.qml",
    "shell/settings/SettingsActionRow.qml",
    "shell/settings/SettingsStepperRow.qml",
    "shell/settings/SettingsSegmentedRow.qml",
] + [f"shell/settings/pages/{name}" for name in PAGES.values()]

CONFIG_KEYS = [
    "appearance.font.scale",
    "general.language",
    "services.clockFormat",
    "general.battery.criticalLevel",
    "utilities.toasts.chargingChanged",
]

# These must not appear in the settings implementation. Device changes go
# through Quickshell's NetworkManager/PipeWire/UPower APIs instead.
FORBIDDEN = [
    r"\bsudo\b",
    r"\bpkexec\b",
    r"\bsystemctl\b",
    r"\bpacman\b",
    r"\bmount\b",
    r"\bnmcli\b",
    r"\brfkill\b",
    r"\biw\s+dev\b",
    r"\bip\s+link\b",
]


def fail(message: str) -> None:
    print(f"FAIL {message}", file=sys.stderr)
    raise SystemExit(1)


def check_static() -> None:
    for relative in REQUIRED_FILES:
        path = ROOT / relative
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"missing settings file: {relative}")
        print(f"ok {relative}")

    store = (ROOT / "shell/components/SettingsStore.qml").read_text(encoding="utf-8")
    for key in CONFIG_KEYS:
        if key not in store:
            fail(f"settings store does not persist {key}")
        print(f"ok config key {key}")

    surface = (ROOT / "shell/surfaces/SettingsSurface.qml").read_text(encoding="utf-8")
    for page in PAGES:
        if f'case "{page}"' in surface or f'id: "{page}"' in surface:
            print(f"ok page {page}")
        else:
            fail(f"settings surface does not route {page}")

    implementation = "\n".join(
        (ROOT / relative).read_text(encoding="utf-8")
        for relative in REQUIRED_FILES
    )
    for pattern in FORBIDDEN:
        if re.search(pattern, implementation):
            fail(f"settings implementation contains forbidden command: {pattern}")
    print("ok no privileged or destructive network commands in settings code")

    shell = (ROOT / "shell/shell.qml").read_text(encoding="utf-8")
    if 'function settingsPage(page: string)' not in shell:
        fail("shell IPC has no settingsPage command")
    if 'SettingsSurface {' not in shell:
        fail("shell does not host SettingsSurface")
    print("ok shell hosts settings and IPC")


def check_config(path: Path) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read persisted config {path}: {error}")

    def at(key: str):
        value = data
        for part in key.split("."):
            if not isinstance(value, dict) or part not in value:
                fail(f"persisted config is missing {key}")
            value = value[part]
        return value

    if at("appearance.font.scale") != 1.1:
        fail("display scale was not persisted")
    if at("general.language") != "pt-BR":
        fail("language was not persisted")
    if at("services.clockFormat") != "TwentyFourHour":
        fail("clock format was not persisted")
    if at("general.battery.criticalLevel") != 15:
        fail("battery critical level was not persisted")
    if at("utilities.toasts.chargingChanged") is not False:
        fail("charging notification preference was not persisted")
    if at("existing.keep") is not True:
        fail("settings write did not preserve unknown keys")

    print("ok persisted settings use the existing Padilha config keys")
    print("ok unknown config keys are preserved")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, help="persisted shell.json to validate")
    args = parser.parse_args()

    check_static()
    if args.config is not None:
        check_config(args.config)
    return 0


if __name__ == "__main__":
    sys.exit(main())
