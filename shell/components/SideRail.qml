// Side navigation for landscape.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Theme theme
    required property ShellState state
    signal navigate(string surface)

    implicitWidth: 96

    Rectangle {
        anchors.fill: parent
        color: root.theme.surfaceContainer
    }
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 1
        color: root.theme.outlineVariant
    }

    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 16
        spacing: 8

        NavItem {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            theme: root.theme
            state: root.state
            icon: "home"
            label: "Home"
            surface: "home"
            onClicked: root.navigate("home")
        }
        NavItem {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            theme: root.theme
            state: root.state
            icon: "apps"
            label: "Apps"
            surface: "launcher"
            onClicked: root.navigate("launcher")
        }
        NavItem {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            theme: root.theme
            state: root.state
            icon: "bell"
            label: "Alerts"
            surface: "notifications"
            onClicked: root.navigate("notifications")
        }
        NavItem {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            theme: root.theme
            state: root.state
            icon: "lock"
            label: "Lock"
            isLock: true
            onClicked: root.state.lock()
        }
        Item { Layout.fillHeight: true }
    }
}
