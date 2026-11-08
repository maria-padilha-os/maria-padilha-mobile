// One touch target in the in-shell fallback keyboard. It never takes focus:
// the focused TextInput stays focused and receives committed text through
// ShellState.

import QtQuick

Item {
    id: root

    required property Theme theme
    required property var info
    required property string token
    property bool active: false
    signal activated()

    readonly property string label: info && info.label !== undefined ? info.label : token
    readonly property bool special: info && info.outline !== undefined && info.outline !== "default"

    implicitWidth: 48
    implicitHeight: 48
    scale: tap.pressed ? 0.95 : 1.0

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.onPressAction: root.activated()

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: root.active
            ? root.theme.primary
            : (root.special ? root.theme.surfaceHighest : root.theme.surfaceContainer)
        border.width: root.active ? 0 : 1
        border.color: root.theme.outlineVariant

        Text {
            anchors.centerIn: parent
            width: parent.width - 8
            text: root.label
            color: root.active ? root.theme.primaryText : root.theme.highText
            font.pixelSize: root.label.length > 2 ? 13 : 18
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    Behavior on scale {
        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
    }

    TapHandler {
        id: tap
        onTapped: root.activated()
    }
}
