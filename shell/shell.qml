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
        const reported = Math.min(state.externalKeyboardHeight, root.targetHeight * 0.45);
        if (reported > 0)
            return reported;
        if (!state.keyboardRequested || state.keyboardMode === "inline" || state.keyboardMode === "off")
            return 0;
        return Math.round(root.targetHeight * root.compositorKeyboardFraction);
    }
    readonly property real keyboardInset: state.inlineKeyboardActive
        ? keyboard.panelHeight : root.compositorKeyboardInset
    readonly property string grabPath: Quickshell.env("PADILHA_SHELL_GRAB") || ""
    readonly property int grabDelay: {
        const value = parseInt(Quickshell.env("PADILHA_SHELL_GRAB_DELAY") || "1200", 10);
        return isNaN(value) ? 1200 : Math.max(200, value);
    }
    readonly property bool selfTest: Quickshell.env("PADILHA_SHELL_SELFTEST") === "1"
    readonly property bool telephonySelfTest: Quickshell.env("PADILHA_SHELL_TELEPHONY_SELFTEST") === "1"
    readonly property bool cameraSelfTest: Quickshell.env("PADILHA_SHELL_CAMERA_SELFTEST") === "1"

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
            anchors.fill: parent
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
        interval: 1000
        running: root.selfTest
        onTriggered: {
            console.log("PADILHA_SHELL_SELFTEST_DETAIL",
                theme.source, theme.mode,
                "primary", theme.primary, theme.primaryText, theme.contrastRatio(theme.primaryText, theme.primary),
                "danger", theme.danger, theme.dangerText, theme.contrastRatio(theme.dangerText, theme.danger),
                "rawonprimary", theme._role("onPrimary"), theme.contrastRatio("#ffffff", theme.primary),
                "coloronprimary", theme.contrastRatio(Qt.color("#ffffff"), Qt.color(theme.primary)),
                "best1", theme.bestOn(theme.primary, "#ffffff"),
                "best2", theme.bestOn(theme.primary, theme._role("onPrimary")),
                "prefcont", theme.contrastRatio(theme._role("onPrimary"), theme.primary));
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
            const checks = [
                ["theme-ready", theme.ready],
                ["surface-text", theme.contrastRatio(theme.text, theme.surface) >= 4.5],
                ["container-text", theme.contrastRatio(theme.containerText, theme.surfaceContainer) >= 4.5],
                ["primary-text", theme.contrastRatio(theme.primaryText, theme.primary) >= 4.5],
                ["danger-text", theme.contrastRatio(theme.dangerText, theme.danger) >= 4.5],
                ["inverse-text", theme.contrastRatio(theme.inverseText, theme.inverseSurface) >= 4.5],
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
