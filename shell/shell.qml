// Maria Padilha Mobile — touch-first shell prototype.
//
// One floating fullscreen surface is used deliberately: it runs on any
// Wayland compositor (including Phosh in the QEMU reference image) without
// requiring wlr-layer-shell. The shell keeps its own status bar, navigation,
// launcher, notification centre and lock surface.

import QtQuick
import Quickshell
import Quickshell.Io

import "components"
import "surfaces"

ShellRoot {
    id: root

    readonly property string sizeOverride: Quickshell.env("PADILHA_SHELL_SIZE") || ""
    readonly property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    readonly property var parsedSize: {
        const match = /^([0-9]+)x([0-9]+)$/.exec(root.sizeOverride);
        if (match)
            return { width: Math.max(320, parseInt(match[1], 10)), height: Math.max(320, parseInt(match[2], 10)) };
        if (root.targetScreen && root.targetScreen.width > 0 && root.targetScreen.height > 0)
            return { width: root.targetScreen.width, height: root.targetScreen.height };
        return { width: 720, height: 1280 };
    }
    readonly property int targetWidth: root.parsedSize.width
    readonly property int targetHeight: root.parsedSize.height
    readonly property bool landscape: root.targetWidth > root.targetHeight
    readonly property bool fullScreen: root.sizeOverride.length === 0 && root.targetScreen !== null
    readonly property real uiScale: state.settings.displayScale
    // The body ends above the keyboard. Inline fallback height comes from the
    // panel. A compositor keyboard may report a rectangle; if it does not
    // (common for an external Wayland OSK), reserve a conservative fraction
    // while a field is focused so the focused input cannot be covered.
    readonly property real compositorKeyboardFraction: {
        const override = parseFloat(Quickshell.env("PADILHA_SHELL_KEYBOARD_INSET") || "");
        return isNaN(override)
            ? (root.landscape ? 0.34 : 0.40)
            : Math.max(0, Math.min(0.60, override));
    }
    readonly property real compositorKeyboardInset: {
        if (Quickshell.env("QT_QPA_PLATFORM") === "offscreen")
            return 0;
        const scale = root.uiScale > 0 ? root.uiScale : 1;
        const reported = Math.min(state.externalKeyboardHeight / scale, root.targetHeight * 0.45);
        if (reported > 0)
            return reported;
        if (!state.keyboardRequested || state.keyboardMode === "inline" || state.keyboardMode === "off")
            return 0;
        return Math.round(root.targetHeight * root.compositorKeyboardFraction / scale);
    }
    readonly property real keyboardInset: state.inlineKeyboardActive
        ? keyboard.panelHeight : root.compositorKeyboardInset
    readonly property string grabPath: Quickshell.env("PADILHA_SHELL_GRAB") || ""
    readonly property int grabDelay: {
        const value = parseInt(Quickshell.env("PADILHA_SHELL_GRAB_DELAY") || "1200", 10);
        return isNaN(value) ? 1200 : Math.max(200, value);
    }
    readonly property bool selfTest: Quickshell.env("PADILHA_SHELL_SELFTEST") === "1"
    readonly property bool settingsSelfTest: Quickshell.env("PADILHA_SETTINGS_SELFTEST") === "1"
    readonly property bool telephonySelfTest: Quickshell.env("PADILHA_SHELL_TELEPHONY_SELFTEST") === "1"
    readonly property bool cameraSelfTest: Quickshell.env("PADILHA_SHELL_CAMERA_SELFTEST") === "1"

    // Runtime accessory for the self-test: walk the live item tree and find
    // controls that opted in to the shared touch-target contract. Hidden
    // surfaces are skipped so only what a user could actually tap is checked.
    function _effectivelyVisible(item) {
        let node = item;
        while (node) {
            if (node.visible === false)
                return false;
            node = node.parent;
        }
        return true;
    }

    function _collectTouchTargets(item, result) {
        if (!item)
            return result;
        if (item.objectName === "padilha-touch-target" && root._effectivelyVisible(item))
            result.push(item);
        const children = item.children || [];
        for (let i = 0; i < children.length; ++i)
            root._collectTouchTargets(children[i], result);
        return result;
    }

    Theme {
        id: theme
    }

    ShellState {
        id: state
        theme: theme
    }

    FloatingWindow {
        id: window
        screen: root.targetScreen
        implicitWidth: root.targetWidth
        implicitHeight: root.targetHeight
        fullscreen: root.fullScreen
        color: theme.surface
        visible: true

        Item {
            id: surfaceRoot
            width: parent.width / (root.uiScale > 0 ? root.uiScale : 1)
            height: parent.height / (root.uiScale > 0 ? root.uiScale : 1)
            scale: root.uiScale > 0 ? root.uiScale : 1
            transformOrigin: Item.TopLeft
            focus: true

            Rectangle {
                anchors.fill: parent
                color: theme.surface
            }

            StatusBar {
                id: status
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                landscape: root.landscape
                theme: theme
                state: state
                onNotificationsRequested: state.openSurface("notifications")
            }

            Item {
                id: body
                anchors.top: status.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.keyboardInset

                SideRail {
                    id: rail
                    visible: root.landscape && !state.locked
                    width: 96
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    theme: theme
                    state: state
                    onNavigate: surface => state.openSurface(surface)
                }

                Item {
                    id: contentArea
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: rail.visible ? rail.right : parent.left
                    anchors.right: parent.right

                    NavBar {
                        id: nav
                        visible: !root.landscape && !state.locked
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        theme: theme
                        state: state
                        onNavigate: surface => state.openSurface(surface)
                    }

                    Item {
                        id: surfaceHost
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: nav.visible ? nav.top : parent.bottom

                        HomeSurface {
                            anchors.fill: parent
                            visible: !state.locked && state.surface === "home"
                            landscape: root.landscape
                            theme: theme
                            state: state
                            onAppsRequested: state.openSurface("launcher")
                            onNotificationsRequested: state.openSurface("notifications")
                        }

                        LauncherSurface {
                            anchors.fill: parent
                            visible: !state.locked && state.surface === "launcher"
                            landscape: root.landscape
                            theme: theme
                            state: state
                            onClosed: state.openSurface("home")
                            onAppLaunched: app => state.launch(app)
                        }

                        NotificationsSurface {
                            anchors.fill: parent
                            visible: !state.locked && state.surface === "notifications"
                            landscape: root.landscape
                            theme: theme
                            state: state
                            onClosed: state.openSurface("home")
                        }

                        CallsSurface {
                            anchors.fill: parent
                            visible: !state.locked && state.surface === "calls"
                            landscape: root.landscape
                            theme: theme
                            state: state
                            onClosed: state.openSurface("home")
                        }

                        MessagesSurface {
                            anchors.fill: parent
                            visible: !state.locked && state.surface === "messages"
                            landscape: root.landscape
                            theme: theme
                            state: state
                            onClosed: state.openSurface("home")
                        }

                        SettingsSurface {
                            anchors.fill: parent
                            visible: !state.locked && state.surface === "settings"
                            landscape: root.landscape
                            theme: theme
                            state: state
                            onClosed: state.openSurface("home")
                        }

                        CameraSurface {
                            anchors.fill: parent
                            visible: !state.locked && state.surface === "camera"
                            landscape: root.landscape
                            theme: theme
                            state: state
                            onClosed: state.openSurface("home")
                        }

                        LockSurface {
                            anchors.fill: parent
                            visible: state.locked
                            landscape: root.landscape
                            theme: theme
                            state: state
                        }
                    }
                }

                Toast {
                    id: toast
                    landscape: root.landscape
                    theme: theme
                    state: state
                    onClicked: {
                        if (state.locked)
                            state.toast("Unlock first");
                        else {
                            state.toastVisible = false;
                            state.openSurface("notifications");
                        }
                    }
                }
            }

            KeyboardPanel {
                id: keyboard
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                landscape: root.landscape
                theme: theme
                state: state
            }
        }
    }

    IpcHandler {
        target: "padilha-shell"

        function home() {
            state.openSurface("home");
        }

        function launcher() {
            state.openSurface("launcher");
        }

        function notifications() {
            state.openSurface("notifications");
        }

        function calls() {
            state.openSurface("calls");
        }

        function messages() {
            state.openSurface("messages");
        }

        function settings() {
            state.openSettingsPage("index");
        }

        function settingsPage(page: string) {
            state.openSettingsPage(page);
        }

        function camera() {
            state.openSurface("camera");
        }

        function lock() {
            state.lock();
        }

        function unlock() {
            state.unlock();
        }

        function demoNotification() {
            state.addDemoNotification();
        }

        function status(): string {
            return JSON.stringify({
                surface: state.surface,
                locked: state.locked,
                demo: state.demo,
                notifications: state.notificationCount,
                battery: state.device.batteryLabel,
                batteryState: state.device.batteryState,
                batteryTime: state.device.batteryTimeLabel,
                charging: state.device.charging,
                externalPower: state.device.externalPower,
                network: state.device.networkLabel,
                palette: theme.source,
                mode: theme.mode,
                settingsPage: state.settingsPage,
                displayScale: state.settings.displayScale,
                language: state.settings.language,
                clockFormat: state.settings.clockFormat,
                settingsFile: state.settings.configPath,
                fontScale: theme.fontScale,
                minTouchTarget: theme.minTouchTarget,
                textContrastThreshold: theme.textContrastThreshold,
                nonTextContrastThreshold: theme.nonTextContrastThreshold,
                contrastFailures: theme.contrastFailures(),
                keyboardMode: state.keyboardMode,
                keyboardVisible: state.inlineKeyboardActive,
                keyboardPurpose: state.keyboardPurpose,
                telephony: state.telephony.state,
                telephonyAvailable: state.telephony.available,
                modemPresent: state.telephony.modemPresent,
                operator: state.telephony.operatorName,
                calls: state.telephony.calls.length,
                messages: state.telephony.messages.length,
                camera: state.camera.state,
                cameraAvailable: state.camera.available,
                cameraPresent: state.camera.cameraPresent,
                cameraPermission: state.camera.permission,
                cameraPreview: state.camera.previewMode,
                cameraFallback: state.camera.fallback
            });
        }
    }

    Timer {
        id: grabTimer
        interval: root.grabDelay
        running: root.grabPath.length > 0
        onTriggered: {
            if (!theme.ready) {
                interval = 200;
                restart();
                return;
            }
            surfaceRoot.grabToImage(function(result) {
                const saved = result.saveToFile(root.grabPath);
                console.log("PADILHA_SHELL_GRAB_SAVED", saved, root.grabPath);
                Qt.exit(saved ? 0 : 1);
            });
        }
    }

    Timer {
        id: telephonySelfTestTimer
        interval: 3000
        running: root.telephonySelfTest
        onTriggered: {
            const telephony = state.telephony;
            const checks = [
                ["bridge-enabled", telephony.bridgeEnabled],
                ["state-registered", telephony.state === "registered"],
                ["modem-present", telephony.modemPresent],
                ["operator-name", telephony.operatorName.length > 0],
                ["voice-capability", telephony.canDial],
                ["messaging-capability", telephony.canMessage],
                ["initial-calls", telephony.calls.length === 0],
                ["initial-messages", telephony.messages.length === 0]
            ];
            let failed = 0;
            for (const check of checks) {
                console.log(check[1] ? "ok" : "FAIL", "telephony-selftest", check[0]);
                if (!check[1])
                    ++failed;
            }
            console.log(failed === 0
                ? "PADILHA_SHELL_TELEPHONY_SELFTEST_PASS"
                : "PADILHA_SHELL_TELEPHONY_SELFTEST_FAIL");
            Qt.exit(failed === 0 ? 0 : 1);
        }
    }

    Timer {
        id: settingsSelfTestWriteTimer
        interval: 500
        running: root.settingsSelfTest
        onTriggered: {
            const settings = state.settings;
            if (settings.configEnabled && !settings.configReady) {
                restart();
                return;
            }
            settings.setDisplayScale(1.1);
            settings.setBrightness(0.37);
            settings.setVolume(0.42);
            settings.setMuted(true);
            settings.setLanguage("pt-BR");
            settings.setClockFormat("TwentyFourHour");
            settings.setBatteryCriticalLevel(15);
            settings.setChargingNotifications(false);
            settings.setWifiEnabled(false);
        }
    }

    Timer {
        id: cameraSelfTestTimer
        interval: 5000
        running: root.cameraSelfTest
        onTriggered: {
            const camera = state.camera;
            const checks = [
                ["backend-enabled", camera.bridgeEnabled],
                ["portal-available", camera.portalAvailable],
                ["camera-present", camera.cameraPresent],
                ["permission-granted", camera.permission === "granted"],
                ["state-ready", camera.state === "ready"],
                ["available", camera.available],
                ["can-capture", camera.canCapture],
                ["fallback-test-pattern", camera.fallback === "test-pattern"],
                ["preview-idle", camera.previewMode === "idle"],
                ["no-captured-image", camera.imagePath.length === 0]
            ];
            let failed = 0;
            for (const check of checks) {
                console.log(check[1] ? "ok" : "FAIL", "camera-selftest", check[0]);
                if (!check[1])
                    ++failed;
            }
            console.log(failed === 0
                ? "PADILHA_SHELL_CAMERA_SELFTEST_PASS"
                : "PADILHA_SHELL_CAMERA_SELFTEST_FAIL");
            Qt.exit(failed === 0 ? 0 : 1);
        }
    }

    Timer {
        id: selfTestTimer
        interval: root.settingsSelfTest ? 2400 : 1000
        running: root.selfTest
        onTriggered: {
            console.log("PADILHA_SHELL_SELFTEST_DETAIL",
                "palette", theme.source, "mode", theme.mode,
                "fontScale", theme.fontScale,
                "minTouchTarget", theme.minTouchTarget,
                "textContrast", theme.textContrastThreshold,
                "nonTextContrast", theme.nonTextContrastThreshold);
            const contrastFailures = theme.contrastFailures();
            const touchTargets = root._collectTouchTargets(surfaceRoot, []);
            const undersizedTargets = touchTargets.filter(target =>
                target.width + 0.5 < theme.minTouchTarget ||
                target.height + 0.5 < theme.minTouchTarget);
            for (const failure of contrastFailures)
                console.log("FAIL", "selftest", "contrast", failure);
            for (const target of undersizedTargets.slice(0, 8)) {
                console.log("FAIL", "selftest", "touch-target",
                    target.accessibleName || target.objectName,
                    Math.round(target.width) + "x" + Math.round(target.height));
            }
            const beforeNotify = state.notificationCount;
            state.addDemoNotification();
            const addOk = state.notificationCount === beforeNotify + 1;
            state.clearNotifications();
            const clearOk = state.notificationCount === 0;
            state.lock();
            const lockOk = state.locked;
            state.appendPin("1");
            state.appendPin("2");
            const pinOk = state.pin === "12";
            state.unlock();
            const unlockOk = !state.locked;
            const termRows = state.keyboardLayouts.rowsFor("terminal", "base").join(" ");
            const urlRows = state.keyboardLayouts.rowsFor("url", "base").join(" ");
            const passwordRows = state.keyboardLayouts.rowsFor("password", "base").join(" ");
            const keyboardAvoidanceOk = root.compositorKeyboardFraction > 0;

            const originalSurface = state.surface;
            const originalPage = state.settingsPage;
            let settingsNavigationOk = true;
            for (const page of ["network", "display", "sound", "battery", "language", "about"]) {
                state.openSettingsPage(page);
                if (state.surface !== "settings" || state.settingsPage !== page)
                    settingsNavigationOk = false;
            }
            state.openSettingsPage("not-a-page");
            if (state.settingsPage !== "index")
                settingsNavigationOk = false;
            state.openSurface(originalSurface);
            state.settingsPage = originalPage;

            const settings = state.settings;
            const settingsValidationOk =
                settings.normalizeDisplayScale(9) === 1.2 &&
                settings.normalizeDisplayScale(-1) === 1.0 &&
                settings.normalizeLevel(2) === 1 &&
                settings.normalizeLevel(-1) === 0 &&
                settings.normalizeBatteryCriticalLevel(99) === 20 &&
                settings.normalizeBatteryCriticalLevel(0) === 1 &&
                settings.normalizeLanguage("pt-BR") === "pt-BR" &&
                settings.normalizeLanguage("xx") === "" &&
                settings.normalizeClockFormat("TwentyFourHour") === "TwentyFourHour" &&
                settings.normalizeClockFormat("nope") === "Auto";
            const settingsPagesOk = settings.supportedLanguages.length >= 2 &&
                settings.supportedClockFormats.length >= 2 &&
                settings.displayScaleOptions.length >= 3 &&
                ["index", "network", "display", "sound", "battery", "language", "about"]
                    .every(page => state.settingsPages.includes(page));
            const settingsTouchFloorOk = settings.displayScaleOptions
                .every(value => value >= 1.0);
            const settingsFileOk = settings.configPath.endsWith("/shell.json") ||
                settings.configPath.endsWith("shell.json");
            const networkUntouchedOk = settings.demo && settings.networkWriteCount === 0;

            let settingsPersistenceOk = true;
            if (root.settingsSelfTest) {
                let saved = null;
                try {
                    saved = JSON.parse(settings.lastSavedText || "{}");
                } catch (error) {
                    saved = null;
                }
                settingsPersistenceOk = settings.saveCount > 0 && saved !== null &&
                    saved.appearance && saved.appearance.font &&
                    saved.appearance.font.scale === 1.1 &&
                    saved.general && saved.general.language === "pt-BR" &&
                    saved.general.battery && saved.general.battery.criticalLevel === 15 &&
                    saved.services && saved.services.clockFormat === "TwentyFourHour" &&
                    saved.utilities && saved.utilities.toasts &&
                    saved.utilities.toasts.chargingChanged === false;
            }

            const checks = [
                ["theme-ready", theme.ready],
                ["font-scale-range", theme.fontScale >= theme.fontScaleMinimum &&
                    theme.fontScale <= theme.fontScaleMaximum],
                ["touch-target-token", theme.minTouchTarget >= 48],
                ["touch-target-floor", theme.touchTarget(1) === theme.minTouchTarget],
                ["touch-targets-found", touchTargets.length >= 8],
                ["touch-targets-sized", undersizedTargets.length === 0],
                ["keyboard-key-target", keyboard.rowHeight >= theme.minTouchTarget],
                ["contrast-roles", contrastFailures.length === 0],
                ["apps-loaded", state.apps.length > 0],
                ["notification-add", addOk],
                ["notification-clear", clearOk],
                ["battery-present", state.device.hasBattery],
                ["battery-percent", state.device.batteryPercent === 82],
                ["battery-charging", state.device.charging],
                ["battery-time", state.device.batteryTimeLabel.length > 0],
                ["lock", lockOk],
                ["pin-entry", pinOk],
                ["unlock", unlockOk],
                ["keyboard-mode", ["compositor", "inline", "auto", "off"].includes(state.keyboardMode)],
                ["keyboard-text", state.keyboardLayouts.rowsFor("text", "base").length === 4],
                ["keyboard-terminal", termRows.includes("Tab") && termRows.includes("Ctrl") && termRows.includes("↑")],
                ["keyboard-url", urlRows.includes("/") && urlRows.includes(":")],
                ["keyboard-password", passwordRows.includes("1") && passwordRows.includes("BackSpace")],
                ["keyboard-avoidance", keyboardAvoidanceOk],
                ["settings-navigation", settingsNavigationOk],
                ["settings-validation", settingsValidationOk],
                ["settings-pages", settingsPagesOk],
                ["settings-touch-floor", settingsTouchFloorOk],
                ["settings-config-path", settingsFileOk],
                ["settings-network-untouched", networkUntouchedOk],
                ["settings-persistence", settingsPersistenceOk],
                ["settings-scale-valid", settings.displayScaleOptions.includes(settings.displayScale)],
                ["settings-scale-applied", !root.settingsSelfTest ||
                    Math.abs(root.uiScale - 1.1) < 0.001],
                ["telephony-state", state.telephony.state.length > 0],
                ["telephony-demo", state.telephony.demo === true],
                ["telephony-modem", state.telephony.modemPresent === true],
                ["telephony-calls", state.telephony.calls.length >= 0],
                ["telephony-messages", state.telephony.messages.length > 0],
                ["camera-state", state.camera.state.length > 0],
                ["camera-demo", state.camera.demo === true],
                ["camera-fallback", state.camera.fallback === "test-pattern"],
                ["camera-preview", state.camera.previewMode === "test-pattern"]
            ];
            let failed = 0;
            for (const check of checks) {
                console.log(check[1] ? "ok" : "FAIL", "selftest", check[0]);
                if (!check[1])
                    ++failed;
            }
            console.log(failed === 0 ? "PADILHA_SHELL_SELFTEST_PASS" : "PADILHA_SHELL_SELFTEST_FAIL");
            Qt.exit(failed === 0 ? 0 : 1);
        }
    }
}
