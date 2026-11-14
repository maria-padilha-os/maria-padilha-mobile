// One navigation target with a 48 px+ touch area and an optional count badge.

import QtQuick

Item {
    id: root

    required property Theme theme
    required property ShellState state
    property string icon: "home"
    property string label: "Home"
    property string surface: "home"
    property bool isLock: false
    signal clicked()

    implicitWidth: root.theme.touchTarget(72)
    implicitHeight: root.theme.touchTarget(72)

    readonly property bool active: root.isLock ? root.state.locked : (!root.state.locked && root.state.surface === root.surface)

    TouchButton {
        theme: root.theme
        anchors.fill: parent
        icon: root.icon
        label: root.label
        iconSize: 23
        labelSize: 11
        radius: 18
        foreground: root.theme.textMuted
        background: "transparent"
        active: root.active
        activeBackground: root.theme.primaryContainer
        activeForeground: root.theme.primaryContainerText
        onClicked: root.clicked()
    }

    Rectangle {
        visible: root.surface === "notifications" && root.state.notificationCount > 0
        width: 17
        height: 17
        radius: 9
        color: root.theme.danger
        border.width: 2
        border.color: root.theme.surfaceContainer
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: 17
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -20
        Text {
            anchors.centerIn: parent
            text: root.state.notificationCount > 9 ? "9+" : root.state.notificationCount
            color: root.theme.dangerText
            font.pixelSize: root.theme.scaledFont(root.state.notificationCount > 9 ? 8 : 10)
            font.weight: Font.Bold
        }
    }
}
