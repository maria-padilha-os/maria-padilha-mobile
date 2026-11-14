#!/usr/bin/env python3
"""Validate the bundled Padilha palette fixtures and the contrast guard."""

from __future__ import annotations

import json
import sys
from pathlib import Path

REQUIRED = [
    "surface", "surfaceContainer", "surfaceContainerHigh", "onSurface",
    "onSurfaceVariant", "primary", "onPrimary", "primaryContainer",
    "onPrimaryContainer", "secondary", "secondaryContainer", "error",
    "onError", "errorContainer", "onErrorContainer", "success",
    "successContainer", "inverseSurface", "inverseOnSurface", "outline",
    "outlineVariant",
]

# Mirrors Theme.bestOnAll(): a preferred colour is accepted at the requested
# ratio, otherwise the shell tries warm neutrals and then pure black/white.
NEUTRAL_DARK = "#130f0e"
NEUTRAL_LIGHT = "#fcf7f5"
HARD_DARK = "#000000"
HARD_LIGHT = "#ffffff"


def channel(value: float) -> float:
    return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4


def luminance(hex_colour: str) -> float:
    text = hex_colour.lstrip("#")
    r, g, b = (int(text[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def ratio(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def guarded(bg: str, preferred: str, minimum: float = 4.5) -> str:
    if ratio(preferred, bg) >= minimum:
        return preferred
    soft = NEUTRAL_DARK if ratio(NEUTRAL_DARK, bg) >= ratio(NEUTRAL_LIGHT, bg) else NEUTRAL_LIGHT
    if ratio(soft, bg) >= minimum:
        return soft
    return HARD_DARK if ratio(HARD_DARK, bg) >= ratio(HARD_LIGHT, bg) else HARD_LIGHT


def load(path: Path) -> dict:
    data = json.loads(path.read_text())
    assert data.get("mode") in {"light", "dark"}, f"{path}: mode must be light/dark"
    colours = data.get("colours")
    assert isinstance(colours, dict), f"{path}: missing colours object"
    missing = [name for name in REQUIRED if name not in colours]
    assert not missing, f"{path}: missing roles: {', '.join(missing)}"
    return colours


def check_readable(path: Path) -> None:
    colours = load(path)
    checks = [
        ("onSurface", "surface"),
        ("onSurfaceVariant", "surfaceContainer"),
        ("onPrimary", "primary"),
        ("onPrimaryContainer", "primaryContainer"),
        ("onError", "error"),
        ("onErrorContainer", "errorContainer"),
        ("onSuccess", "success"),
        ("onSuccessContainer", "successContainer"),
        ("inverseOnSurface", "inverseSurface"),
    ]
    for fg, bg in checks:
        # Auto roles such as onSurfaceVariant are not required to hit 4.5:1
        # for decorative text, but every themed text role must be >= 3:1.
        minimum = 4.5
        actual = ratio("#" + colours[fg].lstrip("#"), "#" + colours[bg].lstrip("#"))
        assert actual >= minimum, f"{path}: {fg} on {bg} is only {actual:.2f}:1"


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    fallback = root / "shell/palettes/padilha-light.json"
    dark = root / "tests/shell/fixtures/padilha-dark.json"
    broken = root / "tests/shell/fixtures/broken-light.json"

    check_readable(fallback)
    check_readable(dark)

    broken_colours = load(broken)
    raw_text = ratio("#" + broken_colours["onSurface"], "#" + broken_colours["surface"])
    assert raw_text < 4.5, "broken fixture must contain an unreadable raw text role"
    guarded_text = guarded("#" + broken_colours["surface"], "#" + broken_colours["onSurface"])
    assert ratio(guarded_text, "#" + broken_colours["surface"]) >= 4.5

    raw_primary = ratio("#" + broken_colours["onPrimary"], "#" + broken_colours["primary"])
    assert raw_primary < 4.5, "broken fixture must contain an unreadable raw primary role"
    guarded_primary = guarded("#" + broken_colours["primary"], "#" + broken_colours["onPrimary"])
    assert ratio(guarded_primary, "#" + broken_colours["primary"]) >= 4.5

    print(f"ok palette {fallback.relative_to(root)}")
    print(f"ok palette {dark.relative_to(root)}")
    print(f"ok contrast guard fixes the broken light fixture ({raw_text:.2f}:1 -> {ratio(guarded_text, '#' + broken_colours['surface']):.2f}:1)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
