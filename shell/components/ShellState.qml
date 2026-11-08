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
        return ["home", "launcher", "notifications"].includes(requested) ? requested : "home";
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
        if (["home", "launcher", "notifications"].includes(name))
            root.surface = name;
    }

    function lock() {
        root.locked = true;
        root.pin = "";
        root.toastVisible = false;
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
            root.apps = demoApps;
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
        root.apps = real.length > 0 ? real : demoApps;
    }

    function launch(app) {
        if (!app)
            return;
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

    property var demoApps: [
        { name: "Messages", icon: "message", id: "demo.messages", entry: null, demo: true },
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
