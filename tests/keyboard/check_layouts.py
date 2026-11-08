#!/usr/bin/env python3
"""Validate the Padilha Squeekboard layouts and keyboard privacy policy.

This script intentionally has no third-party dependency. It uses PyYAML when
available and otherwise parses the small YAML subset used by the layouts. It
never reads or prints typed text: the layout files contain only key definitions.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAYOUT_DIR = ROOT / "config" / "keyboard" / "layouts"
CONFIG = ROOT / "config" / "keyboard" / "keyboard.conf"
EXPECTED = [
    "us.yaml",
    "us_wide.yaml",
    "terminal/us.yaml",
    "terminal/us_wide.yaml",
    "url/us.yaml",
    "url/us_wide.yaml",
    "pin/us.yaml",
    "pin/us_wide.yaml",
]

failures: list[str] = []
checks = 0


def ok(message: str) -> None:
    global checks
    checks += 1
    print(f"ok {message}")


def bad(message: str) -> None:
    global checks
    checks += 1
    failures.append(message)
    print(f"FAIL {message}", file=sys.stderr)


def split_key_value(text: str) -> tuple[str, str]:
    quote = ""
    escaped = False
    for index, char in enumerate(text):
        if escaped:
            escaped = False
            continue
        if char == "\\" and quote == '"':
            escaped = True
            continue
        if quote:
            if char == quote:
                quote = ""
            continue
        if char in ("'", '"'):
            quote = char
        elif char == ":":
            return text[:index].strip(), text[index + 1 :].strip()
    raise ValueError(f"not a key/value line: {text!r}")


def scalar(value: str):
    value = value.strip()
    if value == "":
        return None
    if value.startswith("{") and value.endswith("}"):
        inner = value[1:-1].strip()
        result = {}
        for part in inner.split(","):
            part = part.strip()
            if not part:
                continue
            key, item = split_key_value(part)
            result[unquote(key)] = scalar(item)
        return result
    if value.startswith('"'):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    if value in ("true", "True"):
        return True
    if value in ("false", "False"):
        return False
    if re.fullmatch(r"-?[0-9]+", value):
        return int(value)
    if re.fullmatch(r"-?[0-9]+\.[0-9]+", value):
        return float(value)
    return value


def unquote(value: str) -> str:
    return str(scalar(value))


def parse_fallback(text: str):
    lines = []
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.strip() == "---":
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        lines.append((indent, raw.strip()))

    def parse_block(index: int, indent: int):
        if index >= len(lines):
            return None, index
        is_sequence = lines[index][1].startswith("- ")
        if is_sequence:
            result = []
            while index < len(lines) and lines[index][0] == indent and lines[index][1].startswith("- "):
                rest = lines[index][1][2:].strip()
                index += 1
                if rest == "":
                    value, index = parse_block(index, lines[index][0])
                else:
                    value = scalar(rest)
                result.append(value)
            return result, index

        result = {}
        while index < len(lines) and lines[index][0] == indent and not lines[index][1].startswith("- "):
            key, rest = split_key_value(lines[index][1])
            key = unquote(key)
            index += 1
            if rest == "":
                child_indent = lines[index][0] if index < len(lines) else indent
                value, index = parse_block(index, child_indent)
            else:
                value = scalar(rest)
            result[key] = value
        return result, index

    if not lines:
        return None
    value, index = parse_block(0, lines[0][0])
    if index != len(lines):
        raise ValueError("unparsed YAML content")
    return value


def load_yaml(path: Path):
    text = path.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore
    except ImportError:
        return parse_fallback(text)
    return yaml.safe_load(text)


def tokens(rows) -> list[str]:
    result = []
    for row in rows or []:
        result.extend(str(row).split())
    return result


def config_values() -> dict[str, str]:
    values = {}
    for raw in CONFIG.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def check_config() -> None:
    if not CONFIG.is_file():
        bad("config/keyboard/keyboard.conf is missing")
        return
    values = config_values()
    expected = {
        "KEYBOARD_BACKEND": "squeekboard",
        "KEYBOARD_PACKAGE": "squeekboard",
        "KEYBOARD_TEXT_INPUT_PROTOCOL": "zwp_text_input_v3",
        "KEYBOARD_INPUT_METHOD_PROTOCOL": "zwp_input_method_v2",
        "KEYBOARD_VIRTUAL_KEYBOARD_PROTOCOL": "zwp_virtual_keyboard_v1",
        "KEYBOARD_SHOW_ON_FOCUS": "true",
        "KEYBOARD_HIDE_ON_BLUR": "true",
        "KEYBOARD_ENABLE_PREDICTION": "false",
        "KEYBOARD_ENABLE_SPELLCHECK": "false",
        "KEYBOARD_STORE_TYPED_TEXT": "false",
        "KEYBOARD_LOG_TYPED_TEXT": "false",
        "KEYBOARD_FIT_PANEL": "true",
    }
    for key, want in expected.items():
        if values.get(key) == want:
            ok(f"config {key}={want}")
        else:
            bad(f"config {key} is {values.get(key)!r}, expected {want!r}")

    for key in ("KEYBOARD_SCALE_PORTRAIT", "KEYBOARD_SCALE_LANDSCAPE"):
        try:
            value = float(values.get(key, ""))
        except ValueError:
            value = -1
        if 0.5 <= value <= 3.0:
            ok(f"config {key} is a sane scale")
        else:
            bad(f"config {key} is not a sane scale: {values.get(key)!r}")

    if values.get("KEYBOARD_INLINE_FALLBACK") in ("compositor", "inline", "auto", "off"):
        ok("config inline fallback mode is known")
    else:
        bad("config inline fallback mode is unknown")

    password_layout = values.get("KEYBOARD_PASSWORD_LAYOUT")
    primary_layout = values.get("KEYBOARD_PRIMARY_LAYOUT")
    if password_layout and password_layout == primary_layout:
        ok("password uses the default sensitive-data layout")
    else:
        bad("password layout must be the default layout (Squeekboard has no password directory)")


def check_layout(path: Path, purpose: str) -> None:
    relative = str(path.relative_to(LAYOUT_DIR))
    try:
        data = load_yaml(path)
    except Exception as error:  # noqa: BLE001 - report the file and parser error
        bad(f"{relative}: cannot parse YAML: {error}")
        return

    if not isinstance(data, dict):
        bad(f"{relative}: top level is not a mapping")
        return
    outlines = data.get("outlines")
    views = data.get("views")
    buttons = data.get("buttons")
    if not isinstance(outlines, dict) or not outlines:
        bad(f"{relative}: missing outlines")
        return
    if not isinstance(views, dict) or "base" not in views:
        bad(f"{relative}: missing views.base")
        return
    if not isinstance(buttons, dict):
        bad(f"{relative}: missing buttons")
        return

    for name, outline in outlines.items():
        if not isinstance(outline, dict):
            bad(f"{relative}: outline {name!r} is not a mapping")
            continue
        for dimension in ("width", "height"):
            value = outline.get(dimension)
            if not isinstance(value, (int, float)) or value <= 0:
                bad(f"{relative}: outline {name!r} has no positive {dimension}")
    ok(f"{relative}: outlines")

    defined = set(buttons)
    used = set()
    allowed_literal = re.compile(r"^.$")
    for view, rows in views.items():
        if not isinstance(rows, list) or not rows:
            bad(f"{relative}: view {view!r} is empty")
            continue
        for row in rows:
            if not isinstance(row, str) or not row.strip():
                bad(f"{relative}: view {view!r} has an empty row")
                continue
            row_tokens = row.split()
            if len(row_tokens) > 13:
                bad(f"{relative}: view {view!r} row has too many keys ({len(row_tokens)})")
            for token in row_tokens:
                used.add(token)
                if token not in defined and not allowed_literal.match(token):
                    bad(f"{relative}: view {view!r} references undefined key {token!r}")
    ok(f"{relative}: views and key references")

    orphans = sorted(defined - used)
    if orphans:
        bad(f"{relative}: unused button definitions: {', '.join(orphans)}")
    else:
        ok(f"{relative}: no orphan button definitions")

    all_tokens = tokens([row for rows in views.values() for row in rows])
    if purpose == "default":
        required = {"space", "BackSpace", "Return", "show_numbers", "show_upper"}
    elif purpose == "terminal":
        required = {"Ctrl", "Alt", "BackSpace", "Return", "space", "/", "-", "|", "↑", "↓", "←", "→"}
        if not ({"Tab"} <= set(all_tokens) or {"Tab-small"} <= set(all_tokens)):
            bad(f"{relative}: terminal layout has no Tab key")
    elif purpose == "url":
        required = {"space", "BackSpace", "Return", "/", ".", ":"}
    elif purpose == "pin":
        required = {str(digit) for digit in range(10)} | {"BackSpace", "Return"}
    else:
        required = set()
    missing = sorted(required - set(all_tokens))
    if missing:
        bad(f"{relative}: missing required tokens: {', '.join(missing)}")
    else:
        ok(f"{relative}: purpose tokens")

    if "<<<" in path.read_text(encoding="utf-8"):
        bad(f"{relative}: unresolved merge marker")


def check_logging_and_privileges() -> None:
    log_pattern = re.compile(
        r"console\.(?:log|debug|info|warn|error)\s*\([^;\n]*"
        r"(?:\.text\b|appQuery|keyboardTarget|keyboardInsert|password|secret)",
        re.IGNORECASE,
    )
    for path in sorted((ROOT / "shell").rglob("*.qml")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if log_pattern.search(line):
                bad(f"{path.relative_to(ROOT)}:{number}: logs typed text")
    ok("shell does not log typed text")

    banned = re.compile(r"\b(sudo|pkexec|systemctl|pacman|mount)\b")
    keyboard_scripts = [
        ROOT / "scripts" / "install-squeekboard.sh",
        ROOT / "tests" / "keyboard.sh",
    ]
    for path in keyboard_scripts:
        if not path.exists():
            continue
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = raw.split("#", 1)[0]
            if banned.search(code):
                bad(f"{path.relative_to(ROOT)}:{number}: privileged command in keyboard tooling")
    ok("keyboard tooling uses no privileged commands")


def main() -> int:
    print("== keyboard layout and policy checks ==")
    check_config()
    for relative in EXPECTED:
        path = LAYOUT_DIR / relative
        if not path.is_file():
            bad(f"missing layout: {relative}")
            continue
        purpose = "default"
        if relative.startswith("terminal/"):
            purpose = "terminal"
        elif relative.startswith("url/"):
            purpose = "url"
        elif relative.startswith("pin/"):
            purpose = "pin"
        check_layout(path, purpose)

    unexpected = sorted(
        str(path.relative_to(LAYOUT_DIR))
        for path in LAYOUT_DIR.rglob("*.yaml")
        if str(path.relative_to(LAYOUT_DIR)) not in EXPECTED
    )
    if unexpected:
        bad(f"unexpected layout files: {', '.join(unexpected)}")
    else:
        ok("layout file set is exact")

    check_logging_and_privileges()

    if failures:
        print(f"\n{len(failures)} keyboard check(s) failed", file=sys.stderr)
        return 1
    print(f"\nall {checks} keyboard checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
