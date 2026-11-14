// About page: device, image, shell and palette information. Everything here is
// read-only; the only process is the local `quickshell --version` query.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import ".."

SettingsPage {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    readonly property SettingsStore settings: root.state.settings
    property string quickshellVersion: root.settings.demo ? "0.3.2" : ""
    property string osPrettyName: root.settings.demo ? "postmarketOS (Nura) · Phosh" : ""
    property string kernel: root.settings.demo ? "6.6.0-padilha" : ""
    property string hostname: root.settings.demo ? "padilha-mobile" : ""
    property string deviceName: root.settings.demo ? "Pine64 PinePhone" : ""

    function osField(text, key) {
        for (const line of String(text || "").split("\n")) {
            if (line.startsWith(key + "="))
                return line.substring(key.length + 1).replace(/^"|"$/g, "");
        }
        return "";
    }

    SettingsSection {
        theme: root.theme
        first: true
        text: "Maria Padilha"
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: hero.implicitHeight + 32
        radius: 20
        color: root.theme.primaryContainer
        border.width: 1
        border.color: root.theme.primary

        ColumnLayout {
            id: hero
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 18
            spacing: 4

            Icon {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                Layout.alignment: Qt.AlignHCenter
                name: "settings"
                color: root.theme.primaryContainerText
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Maria Padilha de Bolso"
                color: root.theme.primaryContainerText
                font.pixelSize: root.theme.scaledFont(24)
                font.weight: Font.DemiBold
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Mobile settings · v" + root.settings.mobileVersion
                color: root.theme.primaryContainerText
                font.pixelSize: root.theme.scaledFont(13)
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "Touch-first shell for the Maria Padilha mobile image"
                color: root.theme.primaryContainerText
                font.pixelSize: root.theme.scaledFont(12)
                wrapMode: Text.WordWrap
            }
        }
    }

    SettingsSection {
        theme: root.theme
        text: "System"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "apps"
        label: "Device"
        value: root.deviceName.length > 0 ? root.deviceName : "Unknown"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "home"
        label: "Hostname"
        value: root.hostname.length > 0 ? root.hostname : "Unknown"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "settings"
        label: "Image"
        value: root.osPrettyName.length > 0 ? root.osPrettyName : "Alpine · Phosh"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "warning"
        label: "Kernel"
        value: root.kernel.length > 0 ? root.kernel : "Unknown"
    }

    SettingsSection {
        theme: root.theme
        text: "Software"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "apps"
        label: "Shell"
        value: "Maria Padilha Mobile"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "apps"
        label: "Quickshell"
        value: root.quickshellVersion.length > 0 ? root.quickshellVersion : "0.3+"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "apps"
        label: "Qt"
        value: Qt.application.version.length > 0 ? Qt.application.version : "Qt 6"
    }

    SettingsSection {
        theme: root.theme
        text: "Appearance"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "brightness"
        label: "Palette"
        value: root.theme.mode === "dark" ? "Dark" : "Light"
        description: root.settings.displayPath(root.theme.source)
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "settings"
        label: "Settings file"
        value: root.settings.configPathDisplay.length > 0
            ? root.settings.configPathDisplay : "Unavailable"
    }

    SettingsSection {
        theme: root.theme
        text: "Privacy"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "lock"
        label: "No telemetry"
        value: "Local only"
        description: "This page reads local files and the Quickshell version; it sends nothing."
    }

    FileView {
        path: "/etc/os-release"
        onLoaded: {
            if (!root.settings.demo)
                root.osPrettyName = root.osField(text(), "PRETTY_NAME");
        }
    }

    FileView {
        path: "/proc/sys/kernel/hostname"
        onLoaded: {
            if (!root.settings.demo)
                root.hostname = text().trim();
        }
    }

    FileView {
        path: "/proc/sys/kernel/osrelease"
        onLoaded: {
            if (!root.settings.demo)
                root.kernel = text().trim();
        }
    }

    FileView {
        path: "/sys/class/dmi/id/product_name"
        printErrors: false
        onLoaded: {
            if (!root.settings.demo)
                root.deviceName = text().trim();
        }
    }

    Process {
        command: ["quickshell", "--version"]
        running: !root.settings.demo
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                root.quickshellVersion = parts.length > 1 ? parts[1] : text.trim();
            }
        }
    }
}
