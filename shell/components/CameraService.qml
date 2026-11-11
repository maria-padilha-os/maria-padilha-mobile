// Camera state for the Padilha camera surface.
//
// libcamera publishes cameras through PipeWire and xdg-desktop-portal owns the
// permission prompt. This component starts one short-lived repository helper
// per action and projects its JSON into QML. It never probes /dev/video* and
// never writes image bytes or capture paths to a log. When no camera or portal
// is present it renders a generated test pattern, clearly labelled, rather
// than a stock photograph.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property string demoEnv: Quickshell.env("PADILHA_CAMERA_DEMO") || ""
    readonly property bool shellDemo: Quickshell.env("PADILHA_SHELL_DEMO") === "1" ||
            Quickshell.env("PADILHA_SHELL_DEMO") === "true"
    readonly property bool demo: root.demoEnv === "1" || root.demoEnv === "true"
        ? true : (root.demoEnv === "0" || root.demoEnv === "false" ? false : root.shellDemo)
    readonly property string backendMode: {
        const mode = String(Quickshell.env("PADILHA_CAMERA_BACKEND") || "auto").toLowerCase();
        if (mode === "off" || mode === "test-pattern")
            return mode;
        return "auto";
    }
    readonly property bool bridgeEnabled: !root.demo && root.backendMode === "auto"
    readonly property bool autoRequest: Quickshell.env("PADILHA_CAMERA_AUTOREQUEST") !== "0"
    readonly property string bridgePath: {
        const override = Quickshell.env("PADILHA_CAMERA_BRIDGE") || "";
        if (override.length > 0)
            return override;
        const url = String(Quickshell.shellPath("../scripts/camera-bridge.py"));
        return decodeURIComponent(url.replace(/^file:\/\//, ""));
    }

    property bool available: false
    property string state: "starting"
    property string permission: "unknown"
    property bool portalAvailable: false
    property bool cameraPresent: false
    property int cameraCount: 0
    property var cameras: []
    property bool pipewireAvailable: false
    property var pipewireCameras: []
    property bool libcameraAvailable: false
    property var libcameraCameras: []
    property string fallback: "test-pattern"
    property string lastError: ""
    property string imagePath: ""
    property string previewMode: "idle"
    property bool imageIsTestPattern: false
    property bool initialized: false
    property bool busy: false
    property bool autoRequestDone: false
    property bool requestInFlight: false

    readonly property bool canRequest: root.portalAvailable && root.cameraPresent &&
            !root.requestInFlight &&
            (root.permission === "not-requested" || root.permission === "denied" ||
             root.permission === "cancelled")
    readonly property bool canCapture: root.available && root.cameraPresent &&
            root.permission === "granted"
    readonly property bool hasLiveFrame: root.previewMode === "camera" && root.imagePath.length > 0
    readonly property bool showsTestPattern: root.previewMode === "test-pattern"

    readonly property string statusLabel: {
        switch (root.state) {
        case "ready":
            return root.available ? "Camera ready" : "Camera state";
        case "no-camera":
            return "No camera";
        case "permission-denied":
            return "Camera access denied";
        case "permission-cancelled":
            return "Camera access cancelled";
        case "portal-unavailable":
            return "Camera portal unavailable";
        case "capture-failed":
            return "Capture failed";
        case "disabled":
            return "Camera backend disabled";
        case "unavailable":
            return "Camera unavailable";
        case "starting":
            return "Starting camera";
        default:
            return "Camera";
        }
    }

    readonly property string statusDetail: {
        switch (root.state) {
        case "ready":
            if (root.permission === "granted")
                return "Camera access is granted for this session. Capture one frame when ready.";
            return "A camera is present. Access is requested through the system portal.";
        case "no-camera":
            return "No camera was detected. The generated test pattern is shown instead; it is not a photograph.";
        case "permission-denied":
            return "The camera portal denied access. Live capture is disabled; the generated test pattern remains available.";
        case "permission-cancelled":
            return "The camera permission request was cancelled. Live capture is disabled; the generated test pattern remains available.";
        case "portal-unavailable":
            return "xdg-desktop-portal is not available, so camera permission cannot be checked. Live capture is disabled.";
        case "capture-failed":
            return "The frame could not be captured. Check the camera stack and try again.";
        case "disabled":
            return "The camera backend is disabled in this build. The generated test pattern is the only preview.";
        case "unavailable":
            return "No camera portal or camera source was found. Use the generated test pattern.";
        default:
            return "Waiting for the camera helper.";
        }
    }

    function _selectFallback(stateName) {
        root.imagePath = "";
        root.previewMode = "test-pattern";
        root.imageIsTestPattern = true;
        if (stateName.length > 0)
            root.state = stateName;
    }

    function _applyState(payload) {
        root.portalAvailable = payload.portal && payload.portal.available === true;
        root.cameraPresent = payload.portal && payload.portal.cameraPresent === true;
        root.cameraCount = Number(payload.cameraCount || 0);
        root.cameras = Array.isArray(payload.cameras) ? payload.cameras : [];
        root.pipewireAvailable = payload.pipewire && payload.pipewire.available === true;
        root.pipewireCameras = payload.pipewire && Array.isArray(payload.pipewire.cameras)
            ? payload.pipewire.cameras : [];
        root.libcameraAvailable = payload.libcamera && payload.libcamera.available === true;
        root.libcameraCameras = payload.libcamera && Array.isArray(payload.libcamera.cameras)
            ? payload.libcamera.cameras : [];
        root.permission = String(payload.permission || "not-requested");
        root.fallback = String(payload.fallback || "test-pattern");
        root.lastError = String(payload.error || "");
        root.initialized = true;
        root.busy = false;
        root.requestInFlight = false;

        if (root.portalAvailable && root.cameraPresent) {
            root.available = true;
            if (root.permission === "denied") {
                root.state = "permission-denied";
                root._selectFallback("permission-denied");
            } else if (root.permission === "cancelled") {
                root.state = "permission-cancelled";
                root._selectFallback("permission-cancelled");
            } else {
                root.state = "ready";
                if (root.previewMode !== "camera") {
                    root.previewMode = "idle";
                    root.imagePath = "";
                    root.imageIsTestPattern = false;
                }
            }
        } else {
            root.available = false;
            root._selectFallback(String(payload.state || "unavailable"));
        }

        if (root.autoRequest && !root.autoRequestDone && root.canRequest) {
            root.autoRequestDone = true;
            root.requestAccess();
        }
    }

    function handleLine(line) {
        const text = String(line || "").trim();
        if (text.length === 0)
            return;
        let payload;
        try {
            payload = JSON.parse(text);
        } catch (error) {
            root.lastError = "camera-protocol";
            return;
        }
        if (!payload || typeof payload !== "object")
            return;

        if (payload.type === "state") {
            root._applyState(payload);
        } else if (payload.type === "capture") {
            if (payload.ok === true && String(payload.path || "").length > 0) {
                root.imagePath = String(payload.path);
                root.previewMode = "camera";
                root.imageIsTestPattern = false;
                root.state = "ready";
                root.available = true;
                root.lastError = "";
            } else {
                root.lastError = "capture-failed";
                root.state = "capture-failed";
            }
            root.busy = false;
        } else if (payload.type === "test-pattern") {
            if (payload.ok === true) {
                root.imagePath = String(payload.path || "");
                root.previewMode = "test-pattern";
                root.imageIsTestPattern = true;
            }
            root.busy = false;
        } else if (payload.type === "error") {
            root.lastError = String(payload.code || "camera-error");
            if (root.lastError === "permission-denied")
                root.state = "permission-denied";
            else if (root.lastError === "permission-cancelled")
                root.state = "permission-cancelled";
            else if (root.lastError === "no-camera")
                root.state = "no-camera";
            else
                root.state = "capture-failed";
            root.busy = false;
            root.requestInFlight = false;
        }
    }

    function handleStderr(line) {
        if (String(line || "").trim().length > 0)
            root.lastError = "camera-stderr";
    }

    function onProcessExited(kind) {
        if (!stateProcess.running && !requestProcess.running && !captureProcess.running)
            root.busy = false;
        if (kind === "request")
            root.requestInFlight = false;
        if (!root.initialized) {
            root.state = root.backendMode === "off" ? "disabled" : "unavailable";
            root._selectFallback(root.state);
            if (root.lastError.length === 0)
                root.lastError = "bridge-exited";
        }
    }

    function _disable() {
        root.available = false;
        root.portalAvailable = false;
        root.cameraPresent = false;
        root.cameraCount = 0;
        root.permission = "unavailable";
        root.initialized = true;
        root.busy = false;
        root.state = "disabled";
        root._selectFallback("disabled");
    }

    function _loadDemo() {
        root.available = true;
        root.portalAvailable = true;
        root.cameraPresent = true;
        root.cameraCount = 1;
        root.cameras = [{
            id: 1,
            name: "padilha-demo-camera",
            description: "Demo camera (generated preview)",
            mediaClass: "Video/Source"
        }];
        root.pipewireAvailable = true;
        root.pipewireCameras = root.cameras;
        root.libcameraAvailable = true;
        root.libcameraCameras = [{
            name: "demo camera",
            detail: "generated preview only"
        }];
        root.permission = "granted";
        root.fallback = "test-pattern";
        root.initialized = true;
        root.busy = false;
        root.state = "ready";
        root.lastError = "";
        root.previewMode = "test-pattern";
        root.imagePath = "";
        root.imageIsTestPattern = true;
    }

    function refresh() {
        if (root.demo) {
            root._loadDemo();
            return;
        }
        if (root.backendMode !== "auto") {
            root._disable();
            return;
        }
        if (root.busy || stateProcess.running)
            return;
        root.busy = true;
        root.lastError = "";
        root.state = "starting";
        stateProcess.running = true;
    }

    function activate() {
        if (!root.initialized && !root.busy)
            root.refresh();
    }

    function requestAccess() {
        if (root.demo) {
            root.permission = "granted";
            root.state = "ready";
            return;
        }
        if (root.backendMode !== "auto") {
            root._disable();
            return;
        }
        if (root.requestInFlight || requestProcess.running)
            return;
        root.autoRequestDone = true;
        root.busy = true;
        root.requestInFlight = true;
        root.lastError = "";
        requestProcess.running = true;
    }

    function capture() {
        if (root.demo) {
            root.useTestPattern();
            return;
        }
        if (!root.cameraPresent) {
            root.useTestPattern();
            return;
        }
        if (root.permission !== "granted") {
            root.requestAccess();
            return;
        }
        if (root.busy || captureProcess.running)
            return;
        root.busy = true;
        root.lastError = "";
        captureProcess.running = true;
    }

    function useTestPattern() {
        root.imagePath = "";
        root.previewMode = "test-pattern";
        root.imageIsTestPattern = true;
    }

    function clearImage() {
        root.imagePath = "";
        root.imageIsTestPattern = false;
        root.previewMode = root.cameraPresent && root.permission === "granted"
            ? "idle" : "test-pattern";
    }

    Component.onCompleted: {
        if (root.demo)
            root._loadDemo();
        else if (root.backendMode !== "auto")
            root._disable();
    }

    Process {
        id: stateProcess
        running: false
        command: ["python3", root.bridgePath, "--state"]
        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => root.handleStderr(data)
        }
        onExited: (code, status) => root.onProcessExited("state")
    }

    Process {
        id: requestProcess
        running: false
        command: ["python3", root.bridgePath, "--request"]
        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => root.handleStderr(data)
        }
        onExited: (code, status) => root.onProcessExited("request")
    }

    Process {
        id: captureProcess
        running: false
        command: ["python3", root.bridgePath, "--capture"]
        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => root.handleStderr(data)
        }
        onExited: (code, status) => root.onProcessExited("capture")
    }
}
