// Maria Padilha palette bridge.
//
// The shell does not own a palette. It reads the colour state written by the
// Maria Padilha desktop theme engine at
// $XDG_STATE_HOME/caelestia/scheme.json and falls back to a bundled Padilha
// palette when that state is absent (for example inside a fresh QEMU guest).
//
// Every foreground role is passed through bestOn(). A generated scheme can be
// internally inconsistent, so the shell refuses to paint light text on a light
// surface: the preferred role is used only when it reaches a readable contrast
// ratio, otherwise a high-contrast neutral is chosen.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property string schemePath: ""
    property string fallbackPath: Qt.resolvedUrl("../palettes/padilha-light.json")
    property string source: "bundled fallback"
    property bool ready: false
    property var data: ({})

    // Accessibility tokens.
    //
    // Text scaling is opt-in through PADILHA_SHELL_FONT_SCALE so the shell
    // follows an accessibility setting without depending on a
    // compositor-specific API. The range covers 80% through the WCAG
    // "resize text" target of 200%. The minimum touch target is 48 logical
    // pixels; an operator may raise it up to 96 with
    // PADILHA_SHELL_TOUCH_TARGET, but never below 48.
    readonly property real fontScaleMinimum: 0.8
    readonly property real fontScaleMaximum: 2.0
    readonly property real fontScale: _readFontScale()
    readonly property int minTouchTarget: _readMinimumTouchTarget()
    readonly property real textContrastThreshold: 4.5
    readonly property real nonTextContrastThreshold: 3.0

    readonly property string mode: data && data.mode ? data.mode : "light"
    readonly property bool dark: mode === "dark"
    readonly property string schemeName: data && data.name ? data.name : "padilha"
    readonly property string variant: data && data.variant ? data.variant : "tonalspot"

    readonly property color surface: _role("surface", "background")
    readonly property color surfaceDim: _role("surfaceDim", "surface")
    readonly property color surfaceLow: _role("surfaceContainerLow", "surface")
    readonly property color surfaceContainer: _role("surfaceContainer", "surface")
    readonly property color surfaceHigh: _role("surfaceContainerHigh", "surfaceContainer")
    readonly property color surfaceHighest: _role("surfaceContainerHighest", "surfaceContainerHigh")
    readonly property color surfaceVariant: _role("surfaceVariant", "surfaceContainer")
    property color text: "#201a18"
    property color textMuted: "#52443f"
    property color containerText: "#201a18"
    property color containerMuted: "#52443f"
    property color highText: "#201a18"
    property color highMuted: "#52443f"
    readonly property color primary: _role("primary")
    property color primaryText: "#ffffff"
    readonly property color primaryContainer: _role("primaryContainer")
    property color primaryContainerText: "#3a0a04"
    readonly property color secondary: _role("secondary")
    property color secondaryText: "#ffffff"
    readonly property color secondaryContainer: _role("secondaryContainer")
    property color secondaryContainerText: "#2c1511"
    readonly property color tertiaryContainer: _role("tertiaryContainer")
    property color tertiaryContainerText: "#251a00"
    property color accent: "#904b3e"
    readonly property color outline: _role("outline")
    readonly property color outlineVariant: _role("outlineVariant")
    readonly property color danger: _role("error")
    property color dangerText: "#ffffff"
    readonly property color dangerContainer: _role("errorContainer")
    property color dangerContainerText: "#410002"
    readonly property color success: _role("success", "tertiary")
    property color successText: "#ffffff"
    readonly property color successContainer: _role("successContainer", "tertiaryContainer")
    property color successContainerText: "#0c1f13"
    readonly property color inverseSurface: _role("inverseSurface", "surfaceContainerHighest")
    property color inverseText: "#ffedea"
    readonly property color scrim: _role("scrim", "shadow")
    readonly property color shadow: _role("shadow", "scrim")

    readonly property var _defaults: ({
            surface: "#fbf8f6",
            surfaceContainer: "#f4ece9",
            surfaceContainerHigh: "#efe6e3",
            surfaceContainerHighest: "#e9dfdc",
            onSurface: "#201a18",
            onSurfaceVariant: "#52443f",
            primary: "#904b3e",
            onPrimary: "#ffffff",
            primaryContainer: "#ffdad4",
            onPrimaryContainer: "#3a0a04",
            secondary: "#775650",
            secondaryContainer: "#ffdad4",
            tertiaryContainer: "#fae0a6",
            error: "#ba1a1a",
            onError: "#ffffff",
            errorContainer: "#ffdad6",
            onErrorContainer: "#410002",
            success: "#4f6354",
            successContainer: "#d1e8d5",
            onSuccess: "#ffffff",
            onSuccessContainer: "#0c1f13",
            inverseSurface: "#392e2c",
            inverseOnSurface: "#ffedea",
            outline: "#857370",
            outlineVariant: "#d8c2be",
            scrim: "#000000",
            shadow: "#000000"
        })

    function _hex(value) {
        if (value === undefined || value === null)
            return "";
        const text = String(value).trim();
        if (text === "" || text === "transparent")
            return text;
        if (text.charAt(0) === "#")
            return text;
        if (text.length === 6)
            return "#" + text;
        if (text.length === 8)
            return "#" + text.substring(0, 6);
        return text;
    }

    function _readFontScale() {
        const raw = parseFloat(Quickshell.env("PADILHA_SHELL_FONT_SCALE") || "");
        if (!isFinite(raw) || raw <= 0)
            return 1.0;
        return Math.max(fontScaleMinimum,
            Math.min(fontScaleMaximum, Math.round(raw * 100) / 100));
    }

    function _readMinimumTouchTarget() {
        const raw = parseInt(Quickshell.env("PADILHA_SHELL_TOUCH_TARGET") || "", 10);
        if (isNaN(raw))
            return 48;
        return Math.max(48, Math.min(96, raw));
    }

    // Every text size in the shell goes through this function. Keeping the
    // tokens unscaled in the component API makes the scale auditable.
    function scaledFont(value) {
        const size = Number(value);
        if (!isFinite(size) || size <= 0)
            return 1;
        return Math.max(1, Math.round(size * fontScale));
    }

    // Interactive components call this so a control can never be smaller than
    // the agreed touch target even if a layout asks for less.
    function touchTarget(value) {
        const size = Number(value);
        if (!isFinite(size) || size <= 0)
            return minTouchTarget;
        return Math.max(minTouchTarget, Math.round(size));
    }

    function _raw(name, fallbackName) {
        if (root.data && root.data.colours) {
            let value = root.data.colours[name];
            if (value === undefined && fallbackName)
                value = root.data.colours[fallbackName];
            if (value !== undefined && value !== null && value !== "")
                return _hex(value);
        }
        if (fallbackName && root._defaults[fallbackName] !== undefined)
            return root._defaults[fallbackName];
        return root._defaults[name] !== undefined ? root._defaults[name] : "#000000";
    }

    function _role(name, fallbackName) {
        return _raw(name, fallbackName);
    }

    function _asColor(value) {
        if (typeof value === "string")
            return Qt.color(value);
        return value;
    }

    function _channel(value) {
        return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    }

    function luminance(value) {
        const c = _asColor(value);
        if (!c || isNaN(c.r))
            return 0;
        return 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);
    }

    function contrastRatio(a, b) {
        const la = luminance(a);
        const lb = luminance(b);
        const high = Math.max(la, lb);
        const low = Math.min(la, lb);
        return (high + 0.05) / (low + 0.05);
    }

    // Pick a neutral foreground that is readable on every background in the
    // list. Soft warm neutrals are tried first; pure black/white are the final
    // safety net, which guarantees at least one of them reaches 4.5:1 for any
    // background colour.
    function _bestNeutral(backgrounds, threshold) {
        const soft = [Qt.rgba(0.075, 0.06, 0.055, 1), Qt.rgba(0.99, 0.97, 0.96, 1)];
        const hard = [Qt.rgba(0, 0, 0, 1), Qt.rgba(1, 1, 1, 1)];
        for (const group of [soft, hard]) {
            let best = group[0];
            let bestMinimum = -1;
            for (const candidate of group) {
                let minimum = Infinity;
                for (const bg of backgrounds)
                    minimum = Math.min(minimum, contrastRatio(candidate, bg));
                if (minimum > bestMinimum) {
                    bestMinimum = minimum;
                    best = candidate;
                }
            }
            if (bestMinimum >= threshold || group === hard)
                return best;
        }
        return hard[0];
    }

    // Return a foreground that is readable on every supplied background. The
    // preferred colour wins only when it reaches the requested WCAG ratio on
    // all of them; otherwise a high-contrast neutral is chosen.
    function bestOnAll(backgrounds, preferred, minimum) {
        const threshold = minimum === undefined ? textContrastThreshold : minimum;
        if (preferred !== undefined && preferred !== null && preferred !== "" &&
                backgrounds.every(bg => contrastRatio(preferred, bg) >= threshold))
            return preferred;
        return _bestNeutral(backgrounds, threshold);
    }

    function bestOn(bg, preferred, minimum) {
        return bestOnAll([bg], preferred, minimum);
    }

    // Role pairs used by the mobile shell. This is the single QML-side list
    // the self-test walks; tests/shell/contrast_check.py mirrors it so the
    // palette can be checked without starting Quickshell.
    function contrastPairs() {
        const pairs = [
            ["text-on-surface", text, surface],
            ["text-on-surface-low", text, surfaceLow],
            ["text-muted-on-surface", textMuted, surface],
            ["text-muted-on-surface-low", textMuted, surfaceLow],
            ["container-text-on-container", containerText, surfaceContainer],
            ["container-text-on-high", containerText, surfaceHigh],
            ["container-muted-on-container", containerMuted, surfaceContainer],
            ["container-muted-on-high", containerMuted, surfaceHigh],
            ["high-text-on-high", highText, surfaceHigh],
            ["high-text-on-highest", highText, surfaceHighest],
            ["high-muted-on-high", highMuted, surfaceHigh],
            ["high-muted-on-highest", highMuted, surfaceHighest],
            ["primary-text-on-primary", primaryText, primary],
            ["primary-container-text", primaryContainerText, primaryContainer],
            ["secondary-text-on-secondary", secondaryText, secondary],
            ["secondary-container-text", secondaryContainerText, secondaryContainer],
            ["tertiary-container-text", tertiaryContainerText, tertiaryContainer],
            ["danger-text-on-danger", dangerText, danger],
            ["danger-container-text", dangerContainerText, dangerContainer],
            ["success-text-on-success", successText, success],
            ["success-container-text", successContainerText, successContainer],
            ["inverse-text-on-inverse", inverseText, inverseSurface],
            ["accent-on-surface", accent, surface],
            ["accent-on-surface-low", accent, surfaceLow],
            ["accent-on-container", accent, surfaceContainer],
            ["accent-on-high", accent, surfaceHigh],
            ["danger-on-surface", danger, surface],
            ["danger-on-high", danger, surfaceHigh],
            ["success-on-surface", success, surface],
            ["success-on-high", success, surfaceHigh]
        ];
        return pairs.map(pair => ({
            name: pair[0],
            foreground: pair[1],
            background: pair[2],
            minimum: textContrastThreshold,
            kind: "text"
        })).concat([
            ["outline-on-surface", outline, surface],
            ["outline-on-container", outline, surfaceContainer],
            ["outline-on-high", outline, surfaceHigh]
        ].map(pair => ({
            name: pair[0],
            foreground: pair[1],
            background: pair[2],
            minimum: nonTextContrastThreshold,
            kind: "non-text"
        })));
    }

    function contrastFailures() {
        const failures = [];
        for (const pair of contrastPairs()) {
            const actual = contrastRatio(pair.foreground, pair.background);
            if (actual + 0.0001 < pair.minimum) {
                failures.push(pair.name + " " + actual.toFixed(2) + ":1 < "
                    + pair.minimum.toFixed(2) + ":1");
            }
        }
        return failures;
    }

    // Guarded roles are assigned explicitly so a palette reload cannot leave a
    // foreground stuck at its pre-load value.
    function _refreshGuarded() {
        text = bestOnAll([surface, surfaceLow], _role("onSurface"));
        textMuted = bestOnAll([surface, surfaceLow], _role("onSurfaceVariant"));
        containerText = bestOnAll([surfaceContainer, surfaceHigh], _role("onSurface"));
        containerMuted = bestOnAll([surfaceContainer, surfaceHigh], _role("onSurfaceVariant"));
        highText = bestOnAll([surfaceHigh, surfaceHighest], _role("onSurface"));
        highMuted = bestOnAll([surfaceHigh, surfaceHighest], _role("onSurfaceVariant"));
        primaryText = bestOn(primary, _role("onPrimary"));
        primaryContainerText = bestOn(primaryContainer, _role("onPrimaryContainer"));
        secondaryText = bestOn(secondary, _role("onSecondary"));
        secondaryContainerText = bestOn(secondaryContainer, _role("onSecondaryContainer"));
        tertiaryContainerText = bestOn(tertiaryContainer, _role("onTertiaryContainer"));
        accent = bestOnAll([surface, surfaceLow, surfaceContainer, surfaceHigh],
            _role("primary"));
        dangerText = bestOn(danger, _role("onError"));
        dangerContainerText = bestOn(dangerContainer, _role("onErrorContainer"));
        successText = bestOn(success, _role("onSuccess"));
        successContainerText = bestOn(successContainer, _role("onSuccessContainer"));
        inverseText = bestOn(inverseSurface, _role("inverseOnSurface"));
    }

    function _apply(text, from) {
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (error) {
            console.warn("padilha-shell: cannot parse palette " + from + ": " + error);
            return false;
        }
        if (!parsed || !parsed.colours || typeof parsed.colours !== "object") {
            console.warn("padilha-shell: palette " + from + " has no colours object");
            return false;
        }
        root.data = parsed;
        root.source = from;
        root.ready = true;
        _refreshGuarded();
        return true;
    }

    function _fallbackIfNeeded() {
        if (root.ready || !fallbackLoader.loaded)
            return;
        const text = fallbackLoader.text();
        if (text && text.length > 0)
            _apply(text, "bundled fallback");
    }

    onSchemePathChanged: {
        root.ready = false;
        root.data = ({});
        _refreshGuarded();
        if (stateLoader)
            stateLoader.reload();
    }

    Component.onCompleted: {
        _refreshGuarded();
        if (!root.schemePath || root.schemePath.length === 0)
            root.schemePath = defaultSchemePath();
    }

    function defaultSchemePath() {
        const explicit = Quickshell.env("PADILHA_SCHEME");
        if (explicit && explicit.length > 0)
            return explicit;
        let stateHome = Quickshell.env("XDG_STATE_HOME");
        if (!stateHome || stateHome.length === 0) {
            const home = Quickshell.env("HOME");
            stateHome = home && home.length > 0 ? home + "/.local/state" : "";
        }
        return stateHome.length > 0 ? stateHome + "/caelestia/scheme.json" : "";
    }

    FileView {
        id: stateLoader
        path: root.schemePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._apply(text(), "existing state")
        onLoadFailed: {
            if (!root.ready)
                root._fallbackIfNeeded();
        }
    }

    FileView {
        id: fallbackLoader
        path: root.fallbackPath
        onLoaded: {
            if (!root.ready)
                root._apply(text(), "bundled fallback");
        }
        onLoadFailed: {
            if (!root.ready) {
                console.warn("padilha-shell: no colour state and no bundled fallback; using neutral defaults");
                root.ready = true;
                root.source = "neutral defaults";
            }
        }
    }

    Timer {
        interval: 500
        running: true
        onTriggered: {
            if (!root.ready) {
                root.ready = true;
                root.source = "neutral defaults";
                _refreshGuarded();
            }
        }
    }
}
