// Display settings: brightness, interface scale and a live scale preview.

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import ".."

SettingsPage {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    readonly property SettingsStore settings: root.state.settings
    readonly property var screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    readonly property var scaleOptions: [
        { value: 1.0, label: "100%" },
        { value: 1.1, label: "110%" },
        { value: 1.2, label: "120%" }
    ]

    SettingsSection {
        theme: root.theme
        first: true
        text: "Brightness"
    }

    SettingsSliderRow {
        theme: root.theme
        icon: "brightness"
        label: "Screen brightness"
        description: root.settings.demo
            ? "Demo value; the real backlight is not touched"
            : (root.settings.backlightAvailable
                ? "Applied directly to the backlight device"
                : "No backlight device is available on this machine")
        value: root.settings.brightness
        valueLabel: Math.round(root.settings.brightness * 100) + "%"
        enabled: root.settings.backlightAvailable
        onMoved: value => root.settings.setBrightness(value)
    }

    SettingsSection {
        theme: root.theme
        text: "Interface scale"
    }

    SettingsSegmentedRow {
        theme: root.theme
        label: "Scale"
        description: "Stored as appearance.font.scale; upscales keep every touch target at 48 px or more"
        options: root.scaleOptions
        currentValue: root.settings.displayScale
        onSelected: value => root.settings.setDisplayScale(value)
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "apps"
        label: "Page canvas"
        value: Math.round(root.width) + " × " + Math.round(root.height)
        description: (root.landscape ? "Landscape" : "Portrait") +
            " · " + Math.round(root.settings.displayScale * 100) + "% scale"
    }

    SettingsSection {
        theme: root.theme
        text: "Preview"
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: preview.implicitHeight + 32
        radius: 18
        color: root.theme.surfaceContainer
        border.width: 1
        border.color: root.theme.outlineVariant

        ColumnLayout {
            id: preview
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 16
            spacing: 6

            Text {
                text: "Maria Padilha"
                color: root.theme.containerText
                font.pixelSize: root.theme.scaledFont(Math.round(24 * root.settings.displayScale))
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: "This sample uses the selected scale. Touch targets stay at least 48 px."
                color: root.theme.containerMuted
                font.pixelSize: root.theme.scaledFont(Math.round(13 * root.settings.displayScale))
                wrapMode: Text.WordWrap
            }
            Rectangle {
                Layout.preferredWidth: Math.round(148 * root.settings.displayScale)
                Layout.preferredHeight: 48
                radius: 14
                color: root.theme.primary
                Text {
                    anchors.centerIn: parent
                    text: "Touch target"
                    color: root.theme.primaryText
                    font.pixelSize: root.theme.scaledFont(14)
                    font.weight: Font.Medium
                }
            }
        }
    }

    SettingsSection {
        theme: root.theme
        text: "Display"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "settings"
        label: "Output"
        value: root.screen ? root.screen.name : "Unknown"
        description: root.screen
            ? root.screen.width + " × " + root.screen.height + " px"
            : "No screen reported"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "brightness"
        label: "Night light"
        value: "System"
        description: "Phosh owns the night-light schedule on the mobile image."
    }
}
