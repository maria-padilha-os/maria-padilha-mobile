// Bottom navigation for portrait.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Theme theme
    required property ShellState state
    signal navigate(string surface)

    implicitHeight: 88

    Rectangle {
        anchors.fill: parent
        color: root.theme.surfaceContainer
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: root.theme.outlineVariant
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 4

        NavItem {
            Layout.fillWidth: true
            Layout.fillHeight: true
            theme: root.theme
            state: root.state
            icon: "home"
            label: "Home"
            surface: "home"
            onClicked: root.navigate("home")
        }
        NavItem {
            Layout.fillWidth: true
            Layout.fillHeight: true
            theme: root.theme
            state: root.state
            icon: "apps"
            label: "Apps"
            surface: "launcher"
            onClicked: root.navigate("launcher")
        }
        NavItem {
            Layout.fillWidth: true
            Layout.fillHeight: true
            theme: root.theme
            state: root.state
            icon: "bell"
            label: "Alerts"
            surface: "notifications"
            onClicked: root.navigate("notifications")
        }
        NavItem {
            Layout.fillWidth: true
            Layout.fillHeight: true
            theme: root.theme
            state: root.state
            icon: "lock"
            label: "Lock"
            isLock: true
            onClicked: root.state.lock()
        }
    }
}
