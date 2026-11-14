// Mobile settings state and persistence.
//
// Preferences are stored in the existing Maria Padilha configuration file,
// $PADILHA_CONFIG_DIR/shell.json (normally ~/.config/padilha/shell.json), using
// the same keys the desktop shell owns. The file is written atomically and
// unknown keys are preserved. No second settings file or schema is introduced.
//
// Device state stays with the service that owns it: NetworkManager for Wi-Fi,
// PipeWire/WirePlumber for audio and the backlight subsystem for brightness.
// In demo mode every device write is suppressed; tests use an explicit
// PADILHA_SETTINGS_CONFIG file and PADILHA_SETTINGS_WRITE=1 when they need to
// exercise persistence.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property bool demo: Quickshell.env("PADILHA_SHELL_DEMO") === "1" ||
            Quickshell.env("PADILHA_SHELL_DEMO") === "true"
    readonly property bool configEnabled: !root.demo ||
            (Quickshell.env("PADILHA_SETTINGS_CONFIG") || "").length > 0
    readonly property bool writeEnabled: root.configEnabled &&
            (!root.demo || Quickshell.env("PADILHA_SETTINGS_WRITE") === "1")

    readonly property string configDir: {
        const explicit = Quickshell.env("PADILHA_CONFIG_DIR") || "";
        if (explicit.length > 0)
            return explicit;
        const configHome = Quickshell.env("XDG_CONFIG_HOME") || "";
        if (configHome.length > 0)
            return configHome + "/padilha";
        const home = Quickshell.env("HOME") || "";
        return home.length > 0 ? home + "/.config/padilha" : "";
    }
    readonly property string configPath: {
        const explicit = Quickshell.env("PADILHA_SETTINGS_CONFIG") || "";
        if (explicit.length > 0)
            return explicit;
        return root.configDir.length > 0 ? root.configDir + "/shell.json" : "";
    }
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configPathDisplay: root.displayPath(root.configPath)
    readonly property string mobileVersion: "0.1.0-prototype"

    readonly property var supportedLanguages: [
        { code: "", label: "Auto", detail: "Use the system locale" },
        { code: "en", label: "English", detail: "English" },
        { code: "pt-BR", label: "Português", detail: "Português (Brasil)" },
        { code: "es", label: "Español", detail: "Español" },
        { code: "fr", label: "Français", detail: "Français" },
        { code: "de", label: "Deutsch", detail: "Deutsch" }
    ]
    readonly property var supportedClockFormats: [
        { value: "Auto", label: "Auto", detail: "Follow the locale" },
        { value: "TwelveHour", label: "12-hour", detail: "1:30 PM" },
        { value: "TwentyFourHour", label: "24-hour", detail: "13:30" }
    ]
    // Only upscaling is offered: shrinking the UI would take the 48 px touch
    // floor below the accessibility target this shell promises.
    readonly property var displayScaleOptions: [1.0, 1.1, 1.2]

    // Validated preferences. Every setter clamps to one of these choices.
    property real displayScale: 1.0
    property real brightness: 0.62
    property bool backlightAvailable: root.demo
    property real demoVolume: 0.65
    property bool demoMuted: false
    property string language: ""
    property string clockFormat: "Auto"
    property int batteryCriticalLevel: 5
    property bool chargingNotifications: true
    property bool wifiEnabledDemo: true
    property int powerProfileDemo: PowerProfile.Balanced
    property int networkWriteCount: 0
    property real _pendingBrightness: -1

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool audioAvailable: root.sink !== null && root.sink !== undefined &&
            root.sink.audio !== null && root.sink.audio !== undefined
    readonly property real volume: root.demo
        ? root.demoVolume
        : (root.audioAvailable ? Math.max(0, Math.min(1, root.sink.audio.volume)) : 0.65)
    readonly property bool muted: root.demo
        ? root.demoMuted
        : (root.audioAvailable ? root.sink.audio.muted : false)

    readonly property var wifiDevice: {
        const devices = Networking.devices.values;
        for (const device of devices) {
            if (device && device.type === DeviceType.Wifi)
                return device;
        }
        return null;
    }
    readonly property bool wifiSupported: root.demo || root.wifiDevice !== null
    readonly property bool wifiEnabled: root.demo ? root.wifiEnabledDemo : Networking.wifiEnabled
    readonly property string wifiInterface: root.demo
        ? "wlan0" : (root.wifiDevice ? root.wifiDevice.name : "")
    readonly property string wifiAddress: root.demo
        ? "192.0.2.42"
        : (root.wifiDevice && root.wifiDevice.address.length > 0 ? root.wifiDevice.address : "")
    readonly property var demoWifiNetworks: [
        {
            name: "Padilha Demo Wi-Fi",
            connected: true,
            known: true,
            security: WifiSecurityType.Wpa2Psk,
            signalStrength: 82,
            address: "192.0.2.42"
        },
        {
            name: "Café Padilha",
            connected: false,
            known: false,
            security: WifiSecurityType.Wpa2Psk,
            signalStrength: 64,
            address: ""
        },
        {
            name: "Padilha Guest",
            connected: false,
            known: false,
            security: WifiSecurityType.Open,
            signalStrength: 38,
            address: ""
        }
    ]
    readonly property var wifiNetworks: {
        if (root.demo)
            return root.demoWifiNetworks;
        const device = root.wifiDevice;
        if (!device || !device.networks)
            return [];
        const list = device.networks.values ? device.networks.values : [];
        return [...list].sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.known !== b.known)
                return a.known ? -1 : 1;
            return String(a.name).localeCompare(String(b.name));
        });
    }

    readonly property int powerProfile: root.demo ? root.powerProfileDemo : PowerProfiles.profile
    readonly property bool powerProfilesAvailable: root.demo || root.powerProfile >= 0

    // Configuration document and save status.
    property var config: ({})
    property bool configReady: false
    property string configError: ""
    property int saveCount: 0
    property string lastSavedText: ""
    property bool _writing: false

    signal configSaved()

    function displayPath(path) {
        const value = String(path || "");
        const home = root.home;
        if (home.length > 0 && value.startsWith(home))
            return "~" + value.substring(home.length);
        return value;
    }

    function _clone(value) {
        try {
            return JSON.parse(JSON.stringify(value || {}));
        } catch (error) {
            return {};
        }
    }

    function _setPath(object, path, value) {
        const parts = String(path).split(".");
        let cursor = object;
        for (let i = 0; i < parts.length - 1; ++i) {
            const part = parts[i];
            if (!cursor[part] || typeof cursor[part] !== "object" || Array.isArray(cursor[part]))
                cursor[part] = {};
            cursor = cursor[part];
        }
        cursor[parts[parts.length - 1]] = value;
    }

    function _valueAt(object, path) {
        let cursor = object;
        for (const part of String(path).split(".")) {
            if (cursor === null || cursor === undefined || typeof cursor !== "object")
                return undefined;
            cursor = cursor[part];
        }
        return cursor;
    }

    function normalizeDisplayScale(value) {
        const number = Number(value);
        if (!isFinite(number))
            return 1.0;
        let best = root.displayScaleOptions[0];
        let distance = Math.abs(number - best);
        for (const option of root.displayScaleOptions) {
            const next = Math.abs(number - option);
            if (next < distance) {
                best = option;
                distance = next;
            }
        }
        return best;
    }

    function normalizeLevel(value) {
        const number = Number(value);
        if (!isFinite(number))
            return 0;
        return Math.max(0, Math.min(1, number));
    }

    function normalizeBatteryCriticalLevel(value) {
        const number = Math.round(Number(value));
        if (!isFinite(number))
            return 5;
        return Math.max(1, Math.min(20, number));
    }

    function normalizeLanguage(value) {
        const code = String(value === undefined || value === null ? "" : value);
        if (code.length === 0)
            return "";
        for (const language of root.supportedLanguages) {
            if (language.code.length > 0 && language.code.toLowerCase() === code.toLowerCase())
                return language.code;
        }
        return "";
    }

    function normalizeClockFormat(value) {
        const requested = String(value === undefined || value === null ? "" : value);
        for (const format of root.supportedClockFormats) {
            if (format.value === requested)
                return format.value;
        }
        return "Auto";
    }

    function normalizePowerProfile(value) {
        const number = Number(value);
        if (number === PowerProfile.PowerSaver || number === PowerProfile.Balanced ||
                number === PowerProfile.Performance)
            return number;
        return PowerProfile.Balanced;
    }

    function languageLabel(code) {
        for (const language of root.supportedLanguages) {
            if (language.code === code)
                return language.label;
        }
        return "Auto";
    }

    function clockFormatLabel(value) {
        for (const format of root.supportedClockFormats) {
            if (format.value === value)
                return format.label;
        }
        return "Auto";
    }

    function powerProfileLabel(value) {
        switch (value) {
        case PowerProfile.PowerSaver:
            return "Power saver";
        case PowerProfile.Performance:
            return "Performance";
        default:
            return "Balanced";
        }
    }

    function _applyConfig() {
        const appearance = root.config.appearance || {};
        const font = appearance.font || {};
        root.displayScale = root.normalizeDisplayScale(font.scale === undefined ? 1.0 : font.scale);

        const general = root.config.general || {};
        root.language = root.normalizeLanguage(general.language);
        const battery = general.battery || {};
        root.batteryCriticalLevel = root.normalizeBatteryCriticalLevel(
            battery.criticalLevel === undefined ? 5 : battery.criticalLevel);

        const services = root.config.services || {};
        root.clockFormat = root.normalizeClockFormat(
            services.clockFormat === undefined ? "Auto" : services.clockFormat);

        const utilities = root.config.utilities || {};
        const toasts = utilities.toasts || {};
        root.chargingNotifications = toasts.chargingChanged === undefined
            ? true : !!toasts.chargingChanged;
    }

    function _applyDefaults() {
        root.displayScale = 1.0;
        root.language = "";
        root.clockFormat = "Auto";
        root.batteryCriticalLevel = 5;
        root.chargingNotifications = true;
    }

    function _readConfig(text) {
        if (!root.configEnabled)
            return;
        let parsed;
        try {
            parsed = JSON.parse(text && text.length > 0 ? text : "{}");
        } catch (error) {
            root.config = {};
            root.configError = "The Padilha config is not valid JSON; using defaults.";
            root.configReady = true;
            root._applyDefaults();
            return;
        }
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            root.config = {};
            root.configError = "The Padilha config root is not an object; using defaults.";
            root.configReady = true;
            root._applyDefaults();
            return;
        }
        root.config = parsed;
        root.configError = "";
        root.configReady = true;
        root._applyConfig();
    }

    function _persist(path, value) {
        const next = root._clone(root.config);
        root._setPath(next, path, value);
        root.config = next;
        if (!root.writeEnabled)
            return;
        root.configError = "";
        if (root.configDir.length > 0)
            Quickshell.execDetached(["mkdir", "-p", root.configDir]);
        writeTimer.restart();
    }

    function _flush() {
        if (!root.writeEnabled || root.configPath.length === 0)
            return;
        root._writing = true;
        configFile.setText(JSON.stringify(root.config, null, 4) + "\n");
    }

    function _captureIfRequested() {
        if (Quickshell.env("PADILHA_SETTINGS_CAPTURE") !== "1")
            return;
        const executable = Quickshell.env("PADILHA_CONFIG") || "padilha-config";
        captureProcess.command = [executable, "capture", "--shell", root.configPath];
        captureProcess.running = true;
    }

    function serializeConfig() {
        return JSON.stringify(root.config, null, 4) + "\n";
    }

    function setDisplayScale(value) {
        const next = root.normalizeDisplayScale(value);
        root.displayScale = next;
        root._persist("appearance.font.scale", next);
        return next;
    }

    function setBrightness(value) {
        const next = root.normalizeLevel(value);
        root.brightness = next;
        if (root.demo)
            return next;
        root.backlightAvailable = true;
        root._pendingBrightness = next;
        brightnessTimer.restart();
        return next;
    }

    function setVolume(value) {
        const next = root.normalizeLevel(value);
        if (root.demo) {
            root.demoVolume = next;
            return next;
        }
        if (root.audioAvailable) {
            root.sink.audio.muted = false;
            root.sink.audio.volume = next;
        }
        return next;
    }

    function setMuted(value) {
        const next = !!value;
        if (root.demo) {
            root.demoMuted = next;
            return next;
        }
        if (root.audioAvailable)
            root.sink.audio.muted = next;
        return next;
    }

    function setLanguage(value) {
        const next = root.normalizeLanguage(value);
        root.language = next;
        root._persist("general.language", next);
        return next;
    }

    function setClockFormat(value) {
        const next = root.normalizeClockFormat(value);
        root.clockFormat = next;
        root._persist("services.clockFormat", next);
        return next;
    }

    function setBatteryCriticalLevel(value) {
        const next = root.normalizeBatteryCriticalLevel(value);
        root.batteryCriticalLevel = next;
        root._persist("general.battery.criticalLevel", next);
        return next;
    }

    function setChargingNotifications(value) {
        const next = !!value;
        root.chargingNotifications = next;
        root._persist("utilities.toasts.chargingChanged", next);
        return next;
    }

    function setWifiEnabled(value) {
        const next = !!value;
        if (root.demo) {
            root.wifiEnabledDemo = next;
            return next;
        }
        root.networkWriteCount += 1;
        Networking.wifiEnabled = next;
        return next;
    }

    function connectNetwork(network) {
        if (!network || root.demo)
            return false;
        root.networkWriteCount += 1;
        network.connect();
        return true;
    }

    function setPowerProfile(value) {
        const next = root.normalizePowerProfile(value);
        if (root.demo) {
            root.powerProfileDemo = next;
            return next;
        }
        PowerProfiles.profile = next;
        return next;
    }

    function _parseBrightness(text) {
        const value = String(text || "").trim();
        if (value.length === 0) {
            root.backlightAvailable = false;
            return;
        }
        let percent = -1;
        for (const field of value.split(",")) {
            if (field.trim().endsWith("%")) {
                percent = parseFloat(field);
                break;
            }
        }
        if (!isFinite(percent) || percent < 0) {
            root.backlightAvailable = false;
            return;
        }
        root.brightness = root.normalizeLevel(percent / 100);
        root.backlightAvailable = true;
    }

    Component.onCompleted: {
        if (!root.configEnabled) {
            root._applyDefaults();
            root.configReady = true;
        }
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        atomicWrites: true
        blockWrites: false
        onLoaded: root._readConfig(text())
        onLoadFailed: {
            if (!root.configReady) {
                root._applyDefaults();
                root.configReady = true;
            }
        }
        onFileChanged: {
            if (!root._writing)
                reload();
        }
        onSaved: {
            root._writing = false;
            root.saveCount += 1;
            root.lastSavedText = configFile.text();
            root.configSaved();
            root._captureIfRequested();
        }
        onSaveFailed: {
            root._writing = false;
            root.configError = "Could not save the Padilha config.";
        }
    }

    Process {
        id: brightnessReader
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null"]
        running: !root.demo
        stdout: StdioCollector {
            onStreamFinished: root._parseBrightness(text)
        }
    }

    Process {
        id: brightnessWriter
    }

    Process {
        id: captureProcess
    }

    Timer {
        id: brightnessTimer
        interval: 120
        onTriggered: {
            if (root._pendingBrightness < 0)
                return;
            if (brightnessWriter.running) {
                restart();
                return;
            }
            const value = root._pendingBrightness;
            root._pendingBrightness = -1;
            brightnessWriter.command = ["brightnessctl", "set", Math.round(value * 100) + "%"];
            brightnessWriter.running = true;
        }
    }

    Timer {
        id: writeTimer
        interval: 80
        onTriggered: root._flush()
    }

    Timer {
        interval: 1500
        running: root.configEnabled && !root.configReady
        onTriggered: {
            if (!root.configReady) {
                root._applyDefaults();
                root.configReady = true;
            }
        }
    }
}
