// Four large PIN dots. Filled dots use the guarded on-surface token.

import QtQuick

Row {
    id: root

    required property Theme theme
    required property ShellState state
    spacing: 14

    Repeater {
        model: 4

        delegate: Rectangle {
            required property int index
            width: 16
            height: 16
            radius: 8
            color: index < root.state.pin.length ? root.theme.text : "transparent"
            border.width: 2
            border.color: index < root.state.pin.length ? root.theme.text : root.theme.outline

            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }
    }
}
