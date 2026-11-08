// Notification centre. The prototype tracks live notifications from
// NotificationServer and seeds demo cards only when demo mode is on.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape
    signal closed()

    readonly property int margin: landscape ? 28 : 22
    readonly property int cardWidth: Math.min(width - margin * 2, 820)

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: root.margin
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            TouchButton {
                icon: "back"
                vertical: false
                iconSize: 22
                background: root.theme.surfaceHigh
                foreground: root.theme.text
                implicitWidth: 52
                implicitHeight: 52
                radius: 16
                onClicked: root.closed()
            }

            Column {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: "Notifications"
                    color: root.theme.text
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                }
                Text {
                    text: root.state.notificationCount === 0
                        ? "Nothing waiting"
                        : root.state.notificationCount + (root.state.notificationCount === 1 ? " item" : " items")
                    color: root.theme.textMuted
                    font.pixelSize: 12
                }
            }

            TouchButton {
                visible: root.state.notificationCount > 0
                icon: "close"
                label: "Clear"
                vertical: false
                iconSize: 17
                labelSize: 12
                implicitHeight: 48
                foreground: root.theme.danger
                background: root.theme.surfaceHigh
                borderColor: root.theme.outlineVariant
                onClicked: root.state.clearNotifications()
            }
        }

        Rectangle {
            visible: root.state.dnd
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 14
            color: root.theme.primaryContainer
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 8
                Icon {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    name: "moon"
                    color: root.theme.primaryContainerText
                }
                Text {
                    Layout.fillWidth: true
                    text: "Focus mode is on"
                    color: root.theme.primaryContainerText
                    font.pixelSize: 13
                }
                TouchButton {
                    icon: "close"
                    iconSize: 16
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 16
                    foreground: root.theme.primaryContainerText
                    onClicked: root.state.dnd = false
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.cardWidth
                height: parent.height
                model: root.state.notifications
                spacing: 10
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: NotificationCard {
                    required property var modelData
                    width: list.width
                    theme: root.theme
                    state: root.state
                    notification: modelData
                    onDismissed: root.state.dismiss(modelData)
                }
            }

            Column {
                visible: root.state.notificationCount === 0
                anchors.centerIn: parent
                spacing: 10
                Icon {
                    width: 40
                    height: 40
                    name: "bell"
                    color: root.theme.textMuted
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "No notifications"
                    color: root.theme.text
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Notifications you receive will appear here."
                    color: root.theme.textMuted
                    font.pixelSize: 13
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
