// Touch status bar: clock, network, battery and the notification entry point.

import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    required property Theme theme
    required property ShellState state
    property bool landscape: false
    signal notificationsRequested()

    implicitHeight: landscape ? 56 : 64

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.surface
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: root.theme.outlineVariant
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.landscape ? 24 : 18
        anchors.rightMargin: root.landscape ? 18 : 10
        spacing: root.landscape ? 16 : 8

        Column {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            Text {
                text: Qt.formatTime(clock.date, "HH:mm")
                color: root.theme.text
                font.pixelSize: root.landscape ? 23 : 25
                font.weight: Font.DemiBold
            }
            Text {
                visible: root.landscape
                text: Qt.formatDate(clock.date, "ddd d MMM")
                color: root.theme.textMuted
                font.pixelSize: 12
            }
        }

        Item { Layout.fillWidth: true }

        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 5
            Icon {
                width: 18
                height: 18
                name: root.state.device.networkIcon
                color: root.state.device.online ? root.theme.accent : root.theme.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: root.landscape
                text: root.state.device.networkShort
                color: root.theme.textMuted
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 4
            Icon {
                width: 22
                height: 18
                name: root.state.device.batteryIcon
                color: root.state.device.batteryPercent >= 0 && root.state.device.batteryPercent <= 20
                    ? root.theme.danger : root.theme.text
                level: root.state.device.batteryLevel
                anchors.verticalCenter: parent.verticalCenter
            }
            Icon {
                visible: root.state.device.charging
                width: 13
                height: 13
                name: "bolt"
                color: root.theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.state.device.batteryLabel
                color: root.theme.textMuted
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Item {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignVCenter

            TouchButton {
                anchors.fill: parent
                icon: "bell"
                iconSize: 23
                foreground: root.theme.text
                activeForeground: root.theme.primaryContainerText
                activeBackground: root.theme.primaryContainer
                radius: 14
                onClicked: root.notificationsRequested()
            }

            Rectangle {
                visible: root.state.notificationCount > 0
                width: 17
                height: 17
                radius: 9
                color: root.theme.danger
                border.width: 2
                border.color: root.theme.surface
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 3
                anchors.rightMargin: 3
                Text {
                    anchors.centerIn: parent
                    text: root.state.notificationCount > 9 ? "9+" : root.state.notificationCount
                    color: root.theme.dangerText
                    font.pixelSize: root.state.notificationCount > 9 ? 8 : 10
                    font.weight: Font.Bold
                }
            }
        }
    }
}
