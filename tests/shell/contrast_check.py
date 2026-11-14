#!/usr/bin/env python3
"""Contrast checks for the generated theme roles used by the mobile shell.

Theme.qml does not paint raw generated roles directly. It resolves every
foreground through bestOn()/bestOnAll(), which keeps the preferred role only
when it reaches the threshold on all of the backgrounds that role can be drawn
on. This script mirrors that resolution and fails when any final text role is
below the agreed WCAG AA normal-text threshold (4.5:1), or any meaningful
outline is below the non-text threshold (3:1).

The role list mirrors Theme.contrastPairs(); the QML self-test walks the same
pairs at runtime. Keeping the check in Python means it also runs on builders
without Quickshell installed.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

TEXT_THRESHOLD = 4.5
NON_TEXT_THRESHOLD = 3.0
SOFT_DARK = "#130f0e"
SOFT_LIGHT = "#fcf7f5"
HARD_DARK = "#000000"
HARD_LIGHT = "#ffffff"


def channel(value: float) -> float:
    return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4


def normalise(value: str) -> str:
    text = str(value).strip()
    if text.startswith("#"):
        text = text[1:]
    if len(text) == 8:
        text = text[:6]
    if len(text) != 6:
        raise ValueError(f"not a 6-digit colour: {value!r}")
    return "#" + text.lower()


def luminance(colour: str) -> float:
    text = normalise(colour).lstrip("#")
    r, g, b = (int(text[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def ratio(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def min_ratio(candidate: str, backgrounds: list[str]) -> float:
    return min(ratio(candidate, background) for background in backgrounds)


def best_on(backgrounds: list[str], preferred: str | None,
            minimum: float = TEXT_THRESHOLD) -> str:
    """Mirror Theme.bestOnAll(): soft neutrals first, then black/white."""
    if preferred is not None and min_ratio(preferred, backgrounds) >= minimum:
        return normalise(preferred)
    for group in ((SOFT_DARK, SOFT_LIGHT), (HARD_DARK, HARD_LIGHT)):
        best = max(group, key=lambda candidate: min_ratio(candidate, backgrounds))
        if min_ratio(best, backgrounds) >= minimum or group == (HARD_DARK, HARD_LIGHT):
            return best
    return HARD_DARK


def load(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text())
    assert data.get("mode") in {"light", "dark"}, f"{path}: mode must be light/dark"
    colours = data.get("colours")
    assert isinstance(colours, dict), f"{path}: missing colours object"
    return {name: normalise(value) for name, value in colours.items()}


def role(colours: dict[str, str], name: str, fallback: str | None = None) -> str:
    if name in colours:
        return colours[name]
    if fallback and fallback in colours:
        return colours[fallback]
    raise KeyError(f"missing palette role {name!r}")


def resolved_roles(colours: dict[str, str]) -> dict[str, str]:
    surface = role(colours, "surface", "background")
    surface_low = role(colours, "surfaceContainerLow", "surface")
    surface_container = role(colours, "surfaceContainer", "surface")
    surface_high = role(colours, "surfaceContainerHigh", "surfaceContainer")
    surface_highest = role(colours, "surfaceContainerHighest", "surfaceContainerHigh")
    primary = role(colours, "primary")
    primary_container = role(colours, "primaryContainer")
    secondary = role(colours, "secondary")
    secondary_container = role(colours, "secondaryContainer")
    tertiary_container = role(colours, "tertiaryContainer")
    danger = role(colours, "error")
    danger_container = role(colours, "errorContainer")
    success = role(colours, "success", "tertiary")
    success_container = role(colours, "successContainer", "tertiaryContainer")
    inverse = role(colours, "inverseSurface", "surfaceContainerHighest")

    return {
        "surface": surface,
        "surfaceLow": surface_low,
        "surfaceContainer": surface_container,
        "surfaceHigh": surface_high,
        "surfaceHighest": surface_highest,
        "text": best_on([surface, surface_low], role(colours, "onSurface")),
        "textMuted": best_on([surface, surface_low], role(colours, "onSurfaceVariant")),
        "containerText": best_on([surface_container, surface_high], role(colours, "onSurface")),
        "containerMuted": best_on([surface_container, surface_high], role(colours, "onSurfaceVariant")),
        "highText": best_on([surface_high, surface_highest], role(colours, "onSurface")),
        "highMuted": best_on([surface_high, surface_highest], role(colours, "onSurfaceVariant")),
        "primary": primary,
        "primaryText": best_on([primary], role(colours, "onPrimary")),
        "primaryContainer": primary_container,
        "primaryContainerText": best_on([primary_container], role(colours, "onPrimaryContainer")),
        "secondary": secondary,
        "secondaryText": best_on([secondary], role(colours, "onSecondary")),
        "secondaryContainer": secondary_container,
        "secondaryContainerText": best_on([secondary_container], role(colours, "onSecondaryContainer")),
        "tertiaryContainer": tertiary_container,
        "tertiaryContainerText": best_on([tertiary_container], role(colours, "onTertiaryContainer")),
        "danger": danger,
        "dangerText": best_on([danger], role(colours, "onError")),
        "dangerContainer": danger_container,
        "dangerContainerText": best_on([danger_container], role(colours, "onErrorContainer")),
        "success": success,
        "successText": best_on([success], role(colours, "onSuccess")),
        "successContainer": success_container,
        "successContainerText": best_on([success_container], role(colours, "onSuccessContainer")),
        "inverseSurface": inverse,
        "inverseText": best_on([inverse], role(colours, "inverseOnSurface")),
        "accent": best_on([surface, surface_low, surface_container, surface_high],
                          role(colours, "primary")),
        "outline": role(colours, "outline"),
    }


TEXT_PAIRS = [
    ("text-on-surface", "text", ["surface"]),
    ("text-on-surface-low", "text", ["surfaceLow"]),
    ("text-muted-on-surface", "textMuted", ["surface"]),
    ("text-muted-on-surface-low", "textMuted", ["surfaceLow"]),
    ("container-text-on-container", "containerText", ["surfaceContainer"]),
    ("container-text-on-high", "containerText", ["surfaceHigh"]),
    ("container-muted-on-container", "containerMuted", ["surfaceContainer"]),
    ("container-muted-on-high", "containerMuted", ["surfaceHigh"]),
    ("high-text-on-high", "highText", ["surfaceHigh"]),
    ("high-text-on-highest", "highText", ["surfaceHighest"]),
    ("high-muted-on-high", "highMuted", ["surfaceHigh"]),
    ("high-muted-on-highest", "highMuted", ["surfaceHighest"]),
    ("primary-text-on-primary", "primaryText", ["primary"]),
    ("primary-container-text", "primaryContainerText", ["primaryContainer"]),
    ("secondary-text-on-secondary", "secondaryText", ["secondary"]),
    ("secondary-container-text", "secondaryContainerText", ["secondaryContainer"]),
    ("tertiary-container-text", "tertiaryContainerText", ["tertiaryContainer"]),
    ("danger-text-on-danger", "dangerText", ["danger"]),
    ("danger-container-text", "dangerContainerText", ["dangerContainer"]),
    ("success-text-on-success", "successText", ["success"]),
    ("success-container-text", "successContainerText", ["successContainer"]),
    ("inverse-text-on-inverse", "inverseText", ["inverseSurface"]),
    ("accent-on-surface", "accent", ["surface"]),
    ("accent-on-surface-low", "accent", ["surfaceLow"]),
    ("accent-on-container", "accent", ["surfaceContainer"]),
    ("accent-on-high", "accent", ["surfaceHigh"]),
    ("danger-on-surface", "danger", ["surface"]),
    ("danger-on-high", "danger", ["surfaceHigh"]),
    ("success-on-surface", "success", ["surface"]),
    ("success-on-high", "success", ["surfaceHigh"]),
]

NON_TEXT_PAIRS = [
    ("outline-on-surface", "outline", ["surface"]),
    ("outline-on-container", "outline", ["surfaceContainer"]),
    ("outline-on-high", "outline", ["surfaceHigh"]),
]


def check_final_roles(path: Path) -> list[str]:
    roles = resolved_roles(load(path))
    failures: list[str] = []
    for name, foreground, backgrounds in TEXT_PAIRS:
        for background in backgrounds:
            actual = ratio(roles[foreground], roles[background])
            if actual + 0.0001 < TEXT_THRESHOLD:
                failures.append(
                    f"{path}: {name} is {actual:.2f}:1, below {TEXT_THRESHOLD:.1f}:1")
    for name, foreground, backgrounds in NON_TEXT_PAIRS:
        for background in backgrounds:
            actual = ratio(roles[foreground], roles[background])
            if actual + 0.0001 < NON_TEXT_THRESHOLD:
                failures.append(
                    f"{path}: {name} is {actual:.2f}:1, below {NON_TEXT_THRESHOLD:.1f}:1")
    return failures


def check_guard_floor() -> list[str]:
    """Every background must find a readable guard foreground."""
    failures: list[str] = []
    for step in range(0, 256, 5):
        background = f"#{step:02x}{step:02x}{step:02x}"
        chosen = best_on([background], background)
        actual = ratio(chosen, background)
        if actual + 0.0001 < TEXT_THRESHOLD:
            failures.append(
                f"guard floor: {chosen} on {background} is {actual:.2f}:1")
    return failures


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[2]
    paths = [Path(arg) for arg in argv[1:]] or [
        root / "shell/palettes/padilha-light.json",
        root / "tests/shell/fixtures/padilha-dark.json",
        root / "tests/shell/fixtures/broken-light.json",
    ]
    failures: list[str] = []
    for path in paths:
        failures.extend(check_final_roles(path))
        if not any(item.startswith(f"{path}:") for item in failures):
            try:
                shown = path.resolve().relative_to(root)
            except ValueError:
                shown = path
            print(f"ok contrast {shown}")
    failures.extend(check_guard_floor())
    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print("ok contrast guard floor across 52 background samples")
    print(f"ok {len(TEXT_PAIRS)} text role pairs and "
          f"{len(NON_TEXT_PAIRS)} non-text role pairs")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
