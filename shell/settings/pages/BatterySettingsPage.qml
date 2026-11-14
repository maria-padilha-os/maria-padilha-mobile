// Battery settings: live battery state, power profile, low-battery threshold
// and charging notifications. Battery and charge-threshold writes stay outside
// this UI; the image's hardware-gated helper owns them.

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../components"
import ".."

SettingsPage {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    readonly property SettingsStore settings: root.state.settings
    readonly property var battery: root.state.device
    readonly property var profileOptions: [
        { value: PowerProfile.PowerSaver, label: "Saver" },
        { value: PowerProfile.Balanced, label: "Balanced" },
        { value: PowerProfile.Performance, label: "Performance" }
    ]

    SettingsSection {
        theme: root.theme
        first: true
        text: "Battery"
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: summary.implicitHeight + 36
        radius: 20
        color: root.battery.batteryCritical || root.battery.batteryLow
            ? root.theme.dangerContainer : root.theme.primaryContainer
        border.width: 1
        border.color: root.battery.batteryCritical || root.battery.batteryLow
            ? root.theme.danger : root.theme.primary

        RowLayout {
            id: summary
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 18
            spacing: 16

            Icon {
                Layout.preferredWidth: 56
                Layout.preferredHeight: 48
                name: root.battery.batteryIcon
                level: root.battery.batteryLevel
                color: root.battery.batteryCritical || root.battery.batteryLow
                    ? root.theme.dangerContainerText : root.theme.primaryContainerText
            }

            Column {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: root.battery.batteryLabel
                    color: root.battery.batteryCritical || root.battery.batteryLow
                        ? root.theme.dangerContainerText : root.theme.primaryContainerText
                    font.pixelSize: root.theme.scaledFont(32)
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: root.battery.batteryState +
                        (root.battery.batteryTimeLabel.length > 0
                            ? " · " + root.battery.batteryTimeLabel : "")
                    color: root.battery.batteryCritical || root.battery.batteryLow
                        ? root.theme.dangerContainerText : root.theme.primaryContainerText
                    font.pixelSize: root.theme.scaledFont(13)
                    elide: Text.ElideRight
                }
            }

            Icon {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                visible: root.battery.charging
                name: "bolt"
                color: root.battery.batteryCritical || root.battery.batteryLow
                    ? root.theme.dangerContainerText : root.theme.primaryContainerText
            }
        }
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "power"
        label: "Power source"
        value: root.battery.externalPower ? "External power" : "Battery"
        description: root.battery.hasBattery ? "UPower display battery" : "No battery; running on AC"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "bolt"
        label: "Charging"
        value: root.battery.charging ? "Yes" : "No"
    }

    SettingsSection {
        theme: root.theme
        text: "Power profile"
    }

    SettingsSegmentedRow {
        theme: root.theme
        label: "Profile"
        description: "Managed by power-profiles-daemon when available"
        options: root.profileOptions
        currentValue: root.settings.powerProfile
        enabled: root.settings.powerProfilesAvailable
        onSelected: value => root.settings.setPowerProfile(value)
    }

    SettingsSection {
        theme: root.theme
        text: "Low battery"
    }

    SettingsStepperRow {
        theme: root.theme
        label: "Critical level"
        description: "Stored as general.battery.criticalLevel"
        value: root.settings.batteryCriticalLevel
        from: 1
        to: 20
        stepSize: 1
        valueSuffix: "%"
        onMoved: value => root.settings.setBatteryCriticalLevel(value)
    }

    SettingsToggleRow {
        theme: root.theme
        icon: "bolt"
        label: "Charging notifications"
        description: "Stored as utilities.toasts.chargingChanged"
        checked: root.settings.chargingNotifications
        onToggled: checked => root.settings.setChargingNotifications(checked)
    }

    SettingsSection {
        theme: root.theme
        text: "Charge policy"
    }

    SettingsInfoRow {
        theme: root.theme
        icon: "warning"
        label: "20–80% charge window"
        value: "Image policy"
        description: "The hardware-gated helper applies it outside the shell; this page never writes it."
    }
}
