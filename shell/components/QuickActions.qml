// Three large touch actions. Network is a status tile (it does not change the
// host network), Focus is a local do-not-disturb toggle, Lock raises the lock
// surface. No privileged or device-daemon calls are made.

import QtQuick
import QtQuick.Layouts

GridLayout {
    id: root

    required property Theme theme
    required property ShellState state
    property bool landscape: false
    columns: 3
    rowSpacing: 10
    columnSpacing: 10

    TouchButton {
        Layout.fillWidth: true
        Layout.preferredHeight: root.landscape ? 76 : 84
        icon: root.state.device.networkIcon
        iconSize: 26
        label: root.state.device.networkShort
        labelSize: 12
        foreground: root.theme.text
        background: root.theme.surfaceHigh
        borderColor: root.theme.outlineVariant
        onClicked: root.state.toast("Network · " + root.state.device.networkLabel)
    }

    TouchButton {
        Layout.fillWidth: true
        Layout.preferredHeight: root.landscape ? 76 : 84
        icon: "moon"
        iconSize: 26
        label: "Focus"
        labelSize: 12
        foreground: root.theme.containerText
        background: root.theme.surfaceHigh
        borderColor: root.theme.outlineVariant
        active: root.state.dnd
        activeBackground: root.theme.primaryContainer
        activeForeground: root.theme.primaryContainerText
        onClicked: {
            root.state.dnd = !root.state.dnd;
            root.state.toast(root.state.dnd ? "Focus mode on" : "Focus mode off");
        }
    }

    TouchButton {
        Layout.fillWidth: true
        Layout.preferredHeight: root.landscape ? 76 : 84
        icon: "lock"
        iconSize: 26
        label: "Lock"
        labelSize: 12
        foreground: root.theme.text
        background: root.theme.surfaceHigh
        borderColor: root.theme.outlineVariant
        onClicked: root.state.lock()
    }
}
