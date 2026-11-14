#!/usr/bin/env python3
"""Static accessibility checks for the mobile shell.

These checks catch the regressions a screenshot cannot see:

* every Text/TextInput font size goes through Theme.scaledFont();
* interactive components use the shared minimum touch-target token;
* every custom TouchButton is wired to Theme and every icon-only button has an
  accessible name;
* visual colours do not leak into components; the only literals allowed are the
  documented fallbacks in Theme.qml, Icon.qml and TouchButton.qml;
* the manual accessibility checklist exists and covers the expected areas.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL = ROOT / "shell"
QML_FILES = sorted(SHELL.rglob("*.qml"))
COLOUR_LITERAL = re.compile(r"(?<![&\w])#[0-9a-fA-F]{3,8}\b")
COLOUR_FALLBACK_FILES = {"Theme.qml", "Icon.qml", "TouchButton.qml"}


def touch_button_blocks(text: str) -> list[list[str]]:
    lines = text.splitlines()
    blocks = []
    for index, line in enumerate(lines):
        if "TouchButton {" not in line:
            continue
        depth = 0
        block = []
        for cursor in range(index, len(lines)):
            block.append(lines[cursor])
            depth += lines[cursor].count("{") - lines[cursor].count("}")
            if depth <= 0 and cursor > index:
                break
        blocks.append(block)
    return blocks


def main() -> int:
    failures: list[str] = []
    theme = (SHELL / "components/Theme.qml").read_text()

    for token in ("fontScale", "scaledFont(", "minTouchTarget", "touchTarget(",
                  "contrastPairs()", "contrastFailures()", "PADILHA_SHELL_FONT_SCALE",
                  "PADILHA_SHELL_TOUCH_TARGET"):
        if token not in theme:
            failures.append(f"Theme.qml is missing accessibility token {token!r}")

    for path in QML_FILES:
        text = path.read_text()
        relative = path.relative_to(ROOT)
        for number, line in enumerate(text.splitlines(), 1):
            if "font.pixelSize:" in line:
                expression = line.split("font.pixelSize:", 1)[1]
                if "scaledFont(" not in expression:
                    failures.append(
                        f"{relative}:{number}: font.pixelSize is not scaled by Theme.scaledFont")
            if "font.pointSize:" in line:
                failures.append(
                    f"{relative}:{number}: font.pointSize bypasses the shared scale")
            for match in COLOUR_LITERAL.finditer(line):
                if path.name not in COLOUR_FALLBACK_FILES:
                    failures.append(
                        f"{relative}:{number}: hardcoded colour {match.group(0)} "
                        "outside the documented fallback files")

    for path in QML_FILES:
        relative = path.relative_to(ROOT)
        for block in touch_button_blocks(path.read_text()):
            start = next((line.strip() for line in block if "TouchButton {" in line), "TouchButton")
            if not any(line.strip().startswith("theme:") for line in block):
                failures.append(f"{relative}: {start} has no Theme binding")
            has_label = any(line.strip().startswith("label:") for line in block)
            has_name = any(line.strip().startswith("accessibleName:") for line in block)
            if not has_label and not has_name:
                failures.append(f"{relative}: icon-only TouchButton has no accessibleName")

    required_targets = {
        "TouchButton.qml": "minTouchTarget",
        "KeyboardKey.qml": "minTouchTarget",
        "NavItem.qml": "touchTarget(",
        "KeyboardPanel.qml": "minTouchTarget",
        "AppTile.qml": "minTouchTarget",
    }
    for filename, token in required_targets.items():
        text = (SHELL / "components" / filename).read_text()
        if token not in text:
            failures.append(f"{filename} does not enforce {token}")

    checklist = ROOT / "docs/accessibility.md"
    if not checklist.is_file():
        failures.append("docs/accessibility.md is missing")
    else:
        text = checklist.read_text()
        for heading in ("Screen reader", "Keyboard", "Touch targets", "Hardcoded"):
            if heading.lower() not in text.lower():
                failures.append(f"docs/accessibility.md does not cover {heading}")
        if "PADILHA_SHELL_FONT_SCALE" not in text:
            failures.append("docs/accessibility.md does not document the font scale")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1

    print(f"ok accessibility tokens and {len(QML_FILES)} QML files")
    print("ok scalable fonts, touch targets, accessible names and colour ownership")
    print("ok manual accessibility checklist")
    return 0


if __name__ == "__main__":
    sys.exit(main())
