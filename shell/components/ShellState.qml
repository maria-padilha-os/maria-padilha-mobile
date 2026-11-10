// Prototype session state: navigation, a local notification list, a demo app
// catalogue, and a lock screen whose PIN is deliberately a stub.

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Item {
    id: root

    visible: false
    width: 0
    height: 0

    required property Theme theme
    readonly property DeviceStatus device: DeviceStatus { demo: root.demo }

    property bool demo: false
    property string surface: "home"
    property bool locked: false
    property bool dnd: false
    property string appQuery: ""
    property string pin: ""
    property string toastMessage: ""
    property bool toastVisible: false
    property var notifications: []
    property var apps: []
    property var latestNotification: null

    readonly property int notificationCount: notifications.length

    // Keyboard state. The compositor keyboard (Squeekboard) is the primary
    // backend; the inline fallback panel is used only when the environment
    // asks for it or an auto-mode compositor never reports a keyboard.
    readonly property KeyboardLayouts keyboardLayouts: KeyboardLayouts {}
    readonly property TelephonyService telephony: TelephonyService {}
    readonly property bool keyboardForced: Quickshell.env("PADILHA_SHELL_KEYBOARD") === "1"
    readonly property string keyboardMode: {
        const mode = String(Quickshell.env("PADILHA_SHELL_OSK") || "compositor").toLowerCase();
        return ["compositor", "inline", "auto", "off"].indexOf(mode) >= 0 ? mode : "compositor";
    }
    readonly property bool externalKeyboardVisible: InputMethod.visible &&
            InputMethod.keyboardRectangle.height > 0
    readonly property real externalKeyboardHeight: externalKeyboardVisible
        ? InputMethod.keyboardRectangle.height : 0
    readonly property bool inlineKeyboardActive: keyboardRequested &&
            (keyboardForced || keyboardMode === "inline" ||
             (keyboardMode === "auto" && keyboardFallbackDue && !externalKeyboardVisible))

    property bool keyboardRequested: false
    property bool keyboardFallbackDue: false
    property bool keyboardShift: false
    property string keyboardModifier: ""
    property string keyboardPurpose: "text"
    property string keyboardView: "base"
    property var keyboardTarget: null

    readonly property var filteredApps: {
        const query = appQuery.trim().toLowerCase();
        if (query.length === 0)
            return apps;
        return apps.filter(app => app.name.toLowerCase().indexOf(query) >= 0);
    }

    signal unlocked()

    function initialSurface() {
        const requested = Quickshell.env("PADILHA_SHELL_SURFACE") || "home";
        if (requested === "lock") {
            root.locked = true;
            return "home";
        }
        return ["home", "launcher", "notifications", "calls", "messages"].includes(requested) ? requested : "home";
    }

    function openSurface(name) {
        if (name === "lock") {
            lock();
            return;
        }
        if (root.locked) {
            toast("Unlock first");
            return;
        }
        if (["home", "launcher", "notifications", "calls", "messages"].includes(name)) {
            if (root.surface !== name)
                hideKeyboard();
            root.surface = name;
        }
    }

    function lock() {
        hideKeyboard();
        root.locked = true;
        root.pin = "";
        root.toastVisible = false;
    }

    function normalizeKeyboardPurpose(purpose) {
        const value = String(purpose || "text").toLowerCase();
        return root.keyboardLayouts.purposes.indexOf(value) >= 0 ? value : "text";
    }

    function attachKeyboard(target, purpose) {
        if (!target)
            return;
        root.keyboardTarget = target;
        root.keyboardPurpose = normalizeKeyboardPurpose(purpose);
        root.keyboardView = "base";
        root.keyboardShift = false;
        root.keyboardModifier = "";
        root.keyboardRequested = true;
        root.keyboardFallbackDue = false;
        if (root.keyboardMode !== "inline" && root.keyboardMode !== "off")
            Qt.inputMethod.show();
        if (root.keyboardMode === "auto" && !root.externalKeyboardVisible)
            keyboardFallbackTimer.restart();
    }

    function requestKeyboard(target, purpose) {
        attachKeyboard(target, purpose);
    }

    function detachKeyboard(target) {
        if (target && root.keyboardTarget && target !== root.keyboardTarget)
            return;
        root.keyboardTarget = null;
        root.keyboardRequested = false;
        root.keyboardFallbackDue = false;
        root.keyboardShift = false;
        root.keyboardModifier = "";
        keyboardFallbackTimer.stop();
        if (root.keyboardMode !== "inline" && root.keyboardMode !== "off")
            Qt.inputMethod.hide();
    }

    function hideKeyboard() {
        if (root.keyboardTarget)
            root.keyboardTarget.focus = false;
        detachKeyboard(null);
    }

    function _selectionRange(target) {
        let start = target.cursorPosition >= 0 ? target.cursorPosition : 0;
        let end = start;
        if (target.selectionStart >= 0 && target.selectionEnd >= 0) {
            start = Math.min(target.selectionStart, target.selectionEnd);
            end = Math.max(target.selectionStart, target.selectionEnd);
        }
        return { start: start, end: end };
    }

    function keyboardInsert(value) {
        const target = root.keyboardTarget;
        if (!target || value === undefined || value === null || String(value).length === 0)
            return;
        const text = String(value);
        const range = _selectionRange(target);
        if (range.end > range.start)
            target.remove(range.start, range.end - range.start);
        target.insert(range.start, text);
        target.cursorPosition = range.start + text.length;
    }

    function keyboardBackspace() {
        const target = root.keyboardTarget;
        if (!target)
            return;
        const range = _selectionRange(target);
        if (range.end > range.start) {
            target.remove(range.start, range.end - range.start);
            target.cursorPosition = range.start;
        } else if (range.start > 0) {
            target.remove(range.start - 1, 1);
            target.cursorPosition = range.start - 1;
        }
    }

    function keyboardReturn() {
        const target = root.keyboardTarget;
        if (target && typeof target.accepted === "function") {
            try {
                target.accepted();
            } catch (error) {
                // A field without an accepted handler simply loses the action.
            }
        }
        hideKeyboard();
    }

    function keyboardMove(delta) {
        const target = root.keyboardTarget;
        if (!target)
            return;
        const range = _selectionRange(target);
        const position = delta < 0 ? range.start : range.end;
        target.cursorPosition = Math.max(0, Math.min(target.text.length, position + delta));
    }

    function keyboardSetView(view) {
        root.keyboardView = root.keyboardLayouts.viewFor(root.keyboardPurpose, view);
        root.keyboardShift = false;
    }

    function unlock() {
        root.locked = false;
        root.pin = "";
        root.surface = "home";
        toast("Unlocked · prototype lock");
        root.unlocked();
    }

    function appendPin(digit) {
        if (!root.locked || root.pin.length >= 4)
            return;
        root.pin += digit;
        if (root.pin.length === 4)
            unlockTimer.restart();
    }

    function backspacePin() {
        if (root.pin.length > 0)
            root.pin = root.pin.substring(0, root.pin.length - 1);
    }

    function toast(message) {
        root.toastMessage = message;
        root.toastVisible = true;
        toastTimer.restart();
    }

    function dismiss(entry) {
        if (!entry)
            return;
        if (entry.raw && entry.raw.dismiss)
            entry.raw.dismiss();
        root.notifications = root.notifications.filter(item => item !== entry);
    }

    function clearNotifications() {
        for (const entry of root.notifications) {
            if (entry.raw && entry.raw.dismiss)
                entry.raw.dismiss();
        }
        root.notifications = [];
    }

    function addDemoNotification() {
        const entry = {
            appName: "Messages",
            summary: "Maria",
            body: "A new demo notification for the touch shell.",
            time: Date.now(),
            urgency: 1,
            raw: null,
            demo: true
        };
        root.notifications = [entry, ...root.notifications];
        root.latestNotification = entry;
        toast(entry.summary + ": " + entry.body);
    }

    function pushTelephonyMessage(message) {
        if (!message)
            return;
        const sender = message.number || "Unknown number";
        const entry = {
            appName: "Messages",
            summary: sender,
            body: message.text || "",
            time: Date.now(),
            urgency: 2,
            raw: null,
            demo: false,
            telephonyPath: message.path || ""
        };
        root.notifications = [entry, ...root.notifications];
        root.latestNotification = entry;
        root.toast("New message from " + sender);
    }

    function pushTelephonyCall(call) {
        if (!call)
            return;
        const caller = call.number || "Unknown number";
        const entry = {
            appName: "Calls",
            summary: "Incoming call",
            body: caller,
            time: Date.now(),
            urgency: 2,
            raw: null,
            demo: false,
            telephonyPath: call.path || ""
        };
        root.notifications = [entry, ...root.notifications];
        root.latestNotification = entry;
        root.toast("Incoming call · " + caller);
    }

    function pushNotification(notification) {
        if (!notification)
            return;
        notification.tracked = true;
        const entry = {
            appName: notification.appName || notification.desktopEntry || "Notification",
            summary: notification.summary || "",
            body: notification.body || "",
            time: Date.now(),
            urgency: notification.urgency,
            raw: notification,
            demo: false
        };
        root.notifications = [entry, ...root.notifications];
        root.latestNotification = entry;
        toast(entry.summary.length > 0 ? entry.summary : entry.body);
    }

    function relativeTime(timestamp) {
        const seconds = Math.max(0, Math.floor((Date.now() - timestamp) / 1000));
        if (seconds < 60)
            return "now";
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60)
            return minutes + "m";
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return hours + "h";
        return Math.floor(hours / 24) + "d";
    }

    function loadApps() {
        if (root.demo) {
            root.apps = root.shellApps.concat(demoApps);
            return;
        }
        const entries = DesktopEntries.applications.values;
        const real = entries
            .filter(entry => !entry.noDisplay && entry.name && entry.name.length > 0)
            .map(entry => ({
                name: entry.name,
                icon: entry.icon,
                id: entry.id,
                entry: entry,
                demo: false
            }))
            .sort((a, b) => a.name.localeCompare(b.name));
        root.apps = root.shellApps.concat(real.length > 0 ? real : demoApps);
    }

    function launch(app) {
        if (!app)
            return;
        if (app.surface) {
            root.openSurface(app.surface);
            return;
        }
        if (app.demo || !app.entry) {
            toast("Prototype app · " + app.name);
            return;
        }
        try {
            app.entry.execute();
            toast("Opening " + app.name);
            root.surface = "home";
        } catch (error) {
            toast("Could not launch " + app.name);
        }
    }

    property var shellApps: [
        { name: "Calls", icon: "phone", id: "shell.calls", entry: null, demo: false, surface: "calls" },
        { name: "Messages", icon: "message", id: "shell.messages", entry: null, demo: false, surface: "messages" }
    ]

    property var demoApps: [
        { name: "Notes", icon: "note", id: "demo.notes", entry: null, demo: true },
        { name: "Gallery", icon: "image", id: "demo.gallery", entry: null, demo: true },
        { name: "Calendar", icon: "calendar", id: "demo.calendar", entry: null, demo: true },
        { name: "Maps", icon: "map", id: "demo.maps", entry: null, demo: true },
        { name: "Music", icon: "music", id: "demo.music", entry: null, demo: true },
        { name: "Files", icon: "folder", id: "demo.files", entry: null, demo: true },
        { name: "Camera", icon: "camera", id: "demo.camera", entry: null, demo: true },
        { name: "Weather", icon: "weather", id: "demo.weather", entry: null, demo: true },
        { name: "Clock", icon: "clock", id: "demo.clock", entry: null, demo: true },
        { name: "Calculator", icon: "calculate", id: "demo.calculator", entry: null, demo: true },
        { name: "Settings", icon: "settings", id: "demo.settings", entry: null, demo: true }
    ]

    Component.onCompleted: {
        root.demo = Quickshell.env("PADILHA_SHELL_DEMO") === "1" ||
                Quickshell.env("PADILHA_SHELL_DEMO") === "true";
        root.surface = initialSurface();
        const initialQuery = Quickshell.env("PADILHA_SHELL_QUERY") || "";
        if (initialQuery.length > 0)
            root.appQuery = initialQuery;
        if (root.locked) {
            const initialPin = Quickshell.env("PADILHA_SHELL_PIN") || "";
            root.pin = initialPin.substring(0, 4).replace(/[^0-9]/g, "");
        }
        loadApps();
        if (root.keyboardForced) {
            root.keyboardPurpose = normalizeKeyboardPurpose(
                Quickshell.env("PADILHA_SHELL_KEYBOARD_PURPOSE") || "text");
            const requestedView = Quickshell.env("PADILHA_SHELL_KEYBOARD_VIEW") || "base";
            root.keyboardView = root.keyboardLayouts.viewFor(root.keyboardPurpose, requestedView);
            root.keyboardRequested = true;
        }
        if (root.demo) {
            const now = Date.now();
            root.notifications = [
                {
                    appName: "Messages", summary: "Maria",
                    body: "The train is at 18:40. See you at the station.",
                    time: now - 120000, urgency: 2, raw: null, demo: true
                },
                {
                    appName: "Calendar", summary: "Design review",
                    body: "Starts in 15 minutes · Studio, second floor",
                    time: now - 900000, urgency: 1, raw: null, demo: true
                },
                {
                    appName: "Padilha", summary: "Battery saver is on",
                    body: "You have about 6 hours left at this charge.",
                    time: now - 3600000, urgency: 0, raw: null, demo: true
                }
            ];
            root.latestNotification = root.notifications[0];
        }
    }

    NotificationServer {
        id: notificationServer
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: false
        onNotification: notification => root.pushNotification(notification)
    }

    Connections {
        target: root.telephony
        function onIncomingCall(call) {
            root.pushTelephonyCall(call);
        }
        function onIncomingMessage(message) {
            root.pushTelephonyMessage(message);
        }
    }

    Timer {
        id: keyboardFallbackTimer
        interval: 700
        onTriggered: root.keyboardFallbackDue = root.keyboardRequested && !root.externalKeyboardVisible
    }

    Timer {
        id: toastTimer
        interval: 3200
        onTriggered: root.toastVisible = false
    }

    Timer {
        id: unlockTimer
        interval: 160
        onTriggered: root.unlock()
    }
}
