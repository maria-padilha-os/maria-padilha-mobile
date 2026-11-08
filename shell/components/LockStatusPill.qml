// Notification count pill shown on the lock surface.

import QtQuick

Rectangle {
    id: root

    required property Theme theme
    required property ShellState state

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 34
    radius: 17
    color: theme.primaryContainer

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon {
            width: 15
            height: 15
            name: "bell"
            color: root.theme.primaryContainerText
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.state.notificationCount + " new"
            color: root.theme.primaryContainerText
            font.pixelSize: 11
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
