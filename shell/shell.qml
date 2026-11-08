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
    readonly property string grabPath: Quickshell.env("PADILHA_SHELL_GRAB") || ""
    readonly property int grabDelay: {
        const value = parseInt(Quickshell.env("PADILHA_SHELL_GRAB_DELAY") || "1200", 10);
        return isNaN(value) ? 1200 : Math.max(200, value);
    }
    readonly property bool selfTest: Quickshell.env("PADILHA_SHELL_SELFTEST") === "1"

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
                network: state.device.networkLabel,
                palette: theme.source,
                mode: theme.mode
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
                ["lock", lockOk],
                ["pin-entry", pinOk],
                ["unlock", unlockOk]
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
