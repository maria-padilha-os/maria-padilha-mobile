// Telephony state for the calls and SMS surfaces.
//
// ModemManager is the modem stack. This component owns one small D-Bus bridge
// process, projects its JSON snapshots into QML properties, and sends user
// actions back. It never writes message text, numbers or SIM credentials to a
// log or to disk. In demo mode it exposes deterministic in-memory data for
// screenshots and offscreen tests without starting the bridge.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property string demoEnv: Quickshell.env("PADILHA_TELEPHONY_DEMO") || ""
    readonly property bool shellDemo: Quickshell.env("PADILHA_SHELL_DEMO") === "1" ||
            Quickshell.env("PADILHA_SHELL_DEMO") === "true"
    readonly property bool demo: root.demoEnv === "1" || root.demoEnv === "true"
        ? true : (root.demoEnv === "0" || root.demoEnv === "false" ? false : root.shellDemo)
    readonly property string backendMode: {
        const mode = String(Quickshell.env("PADILHA_TELEPHONY_BACKEND") || "auto").toLowerCase();
        return mode === "off" ? "off" : "auto";
    }
    readonly property bool sessionBus: Quickshell.env("PADILHA_TELEPHONY_BUS") === "session"
    readonly property string bridgePath: {
        const override = Quickshell.env("PADILHA_TELEPHONY_BRIDGE") || "";
        if (override.length > 0)
            return override;
        const url = String(Quickshell.shellPath("../scripts/telephony-bridge.py"));
        return decodeURIComponent(url.replace(/^file:\/\//, ""));
    }
    readonly property bool bridgeEnabled: !demo && backendMode !== "off"
    property bool bridgeActive: root.bridgeEnabled

    property bool available: false
    property string state: "starting"
    property var modems: []
    property var calls: []
    property var messages: []
    property string lastError: ""
    property bool initialized: false
    property var seenCalls: ({})
    property var seenMessages: ({})

    readonly property bool modemPresent: modems.length > 0
    readonly property var modem: modems.length > 0 ? modems[0] : null
    readonly property string operatorName: modem ? (modem.operatorName || "") : ""
    readonly property string operatorShort: root.operatorName.length > 14
        ? root.operatorName.substring(0, 13) + "…" : root.operatorName
    readonly property int signalQuality: modem ? (modem.signalQuality === undefined ? -1 : modem.signalQuality) : -1
    readonly property bool voiceAvailable: modem ? modem.capabilities && modem.capabilities.voice === true : false
    readonly property bool messagingAvailable: modem ? modem.capabilities && modem.capabilities.messaging === true : false
    readonly property bool emergencyOnly: modem ? modem.emergencyOnly === true : false
    readonly property bool simLocked: state === "locked" || (modem && modem.unlockRequired === true)
    readonly property bool ready: available && modemPresent && (state === "registered" || state === "connected")
    readonly property bool canDial: root.ready && root.voiceAvailable && !root.emergencyOnly
    readonly property bool canMessage: root.ready && root.messagingAvailable

    readonly property string statusLabel: {
        switch (root.state) {
        case "registered":
        case "connected":
            return root.operatorName.length > 0 ? root.operatorName : "Mobile network";
        case "searching":
            return "Searching for network";
        case "initializing":
            return "Starting modem";
        case "locked":
            return "SIM locked";
        case "failed":
            return "Modem failed";
        case "disabled":
            return "Modem disabled";
        case "no-modem":
            return "No modem";
        case "unavailable":
            return "ModemManager unavailable";
        case "starting":
            return "Starting telephony";
        default:
            return "Mobile network unavailable";
        }
    }
    readonly property string statusDetail: {
        switch (root.state) {
        case "registered":
        case "connected":
            if (!root.voiceAvailable && !root.messagingAvailable)
                return "This modem has no voice or SMS capability.";
            if (!root.voiceAvailable)
                return "Calls are not supported by this modem.";
            if (!root.messagingAvailable)
                return "SMS is not supported by this modem.";
            if (root.emergencyOnly)
                return "Only emergency service is registered; calls are disabled in this prototype.";
            return "Calls and SMS are available.";
        case "searching":
            return "The modem is registered but still looking for a network.";
        case "initializing":
            return "ModemManager is probing the modem.";
        case "locked":
            return "Unlock the SIM in the system settings; no PIN is stored by this shell.";
        case "failed":
            return "ModemManager reported a failed modem. Reconnect the modem or restart the service.";
        case "disabled":
            return "The modem is powered down.";
        case "no-modem":
            return "No cellular modem is present, or the device does not have one. Calls and SMS are unavailable.";
        case "unavailable":
            return "ModemManager is not running or cannot be reached on D-Bus.";
        default:
            return "Waiting for ModemManager.";
        }
    }

    signal incomingCall(var call)
    signal incomingMessage(var message)

    function _isDemo() {
        return root.demo;
    }

    function _markSeen() {
        const callMap = ({});
        for (const call of root.calls)
            callMap[call.path] = true;
        const messageMap = ({});
        for (const message of root.messages)
            messageMap[message.path] = true;
        root.seenCalls = callMap;
        root.seenMessages = messageMap;
        root.initialized = true;
    }

    function _applySnapshot(snapshot) {
        const wasAvailable = root.available;
        root.available = snapshot.available === true;
        root.state = snapshot.state || (root.available ? "no-modem" : "unavailable");
        root.modems = Array.isArray(snapshot.modems) ? snapshot.modems : [];
        root.calls = Array.isArray(snapshot.calls) ? snapshot.calls : [];
        root.messages = Array.isArray(snapshot.messages) ? snapshot.messages : [];
        root.lastError = "";
        if (!root.available) {
            root.initialized = false;
            root.seenCalls = ({});
            root.seenMessages = ({});
            return;
        }
        if (!root.initialized) {
            root._markSeen();
            return;
        }
        for (const call of root.calls) {
            if (!root.seenCalls[call.path] &&
                    (call.state === "ringing_in" || call.state === "waiting")) {
                root.incomingCall(call);
            }
            root.seenCalls[call.path] = true;
        }
        for (const message of root.messages) {
            if (!root.seenMessages[message.path] && message.direction === "incoming")
                root.incomingMessage(message);
            root.seenMessages[message.path] = true;
        }
        if (!wasAvailable && root.available)
            root._markSeen();
    }

    function handleLine(line) {
        const text = String(line || "").trim();
        if (text.length === 0)
            return;
        let payload;
        try {
            payload = JSON.parse(text);
        } catch (error) {
            root.lastError = "bridge-protocol";
            return;
        }
        if (!payload || typeof payload !== "object")
            return;
        if (payload.type === "snapshot")
            root._applySnapshot(payload);
        else if (payload.type === "error")
            root.lastError = payload.code || "telephony-error";
    }

    function handleStderr(line) {
        if (String(line || "").trim().length > 0)
            root.lastError = "bridge-stderr";
    }

    function handleBridgeExit(code) {
        root.bridgeActive = false;
        root.available = false;
        root.state = "unavailable";
        root.initialized = false;
        root.lastError = "bridge-exited";
        if (root.bridgeEnabled)
            retryTimer.restart();
    }

    function sendCommand(payload) {
        if (root.demo)
            return false;
        if (!root.bridgeActive || !bridge.running) {
            root.lastError = "telephony-unavailable";
            return false;
        }
        bridge.write(JSON.stringify(payload) + "\n");
        return true;
    }

    function dial(number) {
        const value = String(number || "").trim();
        if (value.length === 0)
            return;
        if (root.demo) {
            if (findCall(value))
                return;
            const call = {
                path: "demo-call-" + Date.now(),
                number: value,
                direction: "outgoing",
                state: "dialing",
                stateLabel: "dialing"
            };
            root.calls = root.calls.concat([call]);
            demoCallTimer.callPath = call.path;
            demoCallTimer.restart();
            return;
        }
        if (!root.canDial) {
            root.lastError = root.simLocked ? "sim-locked" : "calls-unavailable";
            return;
        }
        root.sendCommand({ cmd: "dial", number: value });
    }

    function answer(call) {
        if (!call)
            return;
        if (root.demo) {
            root._setDemoCallState(call.path, "active");
            return;
        }
        root.sendCommand({ cmd: "answer", path: call.path });
    }

    function hangup(call) {
        if (root.demo) {
            root.calls = root.calls.filter(item => !call || item.path !== call.path);
            return;
        }
        if (call && call.path)
            root.sendCommand({ cmd: "hangup", path: call.path });
        else
            root.sendCommand({ cmd: "hangup_all" });
    }

    function sendDtmf(call, digit) {
        if (!call)
            return;
        if (root.demo)
            return;
        root.sendCommand({ cmd: "send_dtmf", path: call.path, digit: String(digit) });
    }

    function sendSms(number, body) {
        const to = String(number || "").trim();
        const text = String(body || "");
        if (to.length === 0 || text.length === 0)
            return false;
        if (root.demo) {
            const message = {
                path: "demo-sms-" + Date.now(),
                number: to,
                text: text,
                direction: "outgoing",
                state: "sent",
                stateLabel: "sent",
                timestamp: new Date().toISOString()
            };
            root.messages = root.messages.concat([message]);
            return true;
        }
        if (!root.canMessage) {
            root.lastError = root.simLocked ? "sim-locked" : "messaging-unavailable";
            return false;
        }
        return root.sendCommand({ cmd: "send_sms", number: to, text: text });
    }

    function deleteMessage(message) {
        if (!message)
            return;
        if (root.demo) {
            root.messages = root.messages.filter(item => item.path !== message.path);
            return;
        }
        root.sendCommand({ cmd: "delete_sms", path: message.path });
    }

    function refresh() {
        if (root.demo)
            return;
        root.sendCommand({ cmd: "refresh" });
    }

    function findCall(number) {
        for (const call of root.calls) {
            if (call.number === number && call.state !== "terminated")
                return call;
        }
        return null;
    }

    function _setDemoCallState(path, stateName) {
        const updated = [];
        for (const call of root.calls) {
            if (call.path === path) {
                const copy = Object.assign({}, call);
                copy.state = stateName;
                copy.stateLabel = stateName;
                updated.push(copy);
            } else {
                updated.push(call);
            }
        }
        root.calls = updated;
    }

    function _loadDemo() {
        root.available = true;
        root.state = "registered";
        root.modems = [{
            path: "demo-modem",
            manufacturer: "Padilha",
            model: "Prototype modem",
            state: "registered",
            stateLabel: "registered",
            operatorName: "Padilha Mobile",
            signalQuality: 72,
            unlockRequired: false,
            emergencyOnly: false,
            voice: true,
            messaging: true,
            capabilities: { voice: true, messaging: true }
        }];
        const marker = Quickshell.env("PADILHA_TELEPHONY_MESSAGE") || "";
        const demoMessages = [
            {
                path: "demo-sms-1",
                number: "+15550100001",
                text: "The train is at 18:40. See you at the station.",
                direction: "incoming",
                state: "received",
                stateLabel: "received",
                timestamp: "2026-11-10T10:10:00+00:00"
            },
            {
                path: "demo-sms-2",
                number: "+15550100002",
                text: "On my way. I will call when I arrive.",
                direction: "outgoing",
                state: "sent",
                stateLabel: "sent",
                timestamp: "2026-11-10T10:12:00+00:00"
            }
        ];
        if (marker.length > 0) {
            demoMessages.push({
                path: "demo-sms-marker",
                number: "+15550100003",
                text: marker,
                direction: "incoming",
                state: "received",
                stateLabel: "received",
                timestamp: "2026-11-10T10:14:00+00:00"
            });
        }
        root.messages = demoMessages;
        root.calls = [];
        root._markSeen();
    }

    Component.onCompleted: {
        if (root.demo) {
            root._loadDemo();
            return;
        }
        if (root.backendMode === "off") {
            root.available = false;
            root.state = "no-modem";
        }
    }

    Process {
        id: bridge
        running: root.bridgeActive
        stdinEnabled: true
        command: ["python3", root.bridgePath].concat(root.sessionBus ? ["--session-bus"] : [])
        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => root.handleStderr(data)
        }
        onExited: (code, status) => root.handleBridgeExit(code)
    }

    Timer {
        id: retryTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.bridgeEnabled && !root.bridgeActive)
                root.bridgeActive = true;
        }
    }

    Timer {
        id: demoCallTimer
        property string callPath: ""
        interval: 700
        onTriggered: root._setDemoCallState(root.callPath, "active")
    }
}
