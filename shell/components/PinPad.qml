// Large numeric keypad for the prototype lock surface.

import QtQuick
import QtQuick.Layouts

GridLayout {
    id: root

    required property Theme theme
    required property ShellState state
    property bool landscape: false
    property int keyHeight: landscape ? 54 : 64
    signal digitPressed(string digit)

    columns: 3
    rowSpacing: 10
    columnSpacing: 10

    Repeater {
        model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "backspace", "0", "check"]

        delegate: TouchButton {
            required property string modelData
            Layout.fillWidth: true
            Layout.preferredHeight: root.keyHeight
            icon: modelData === "backspace" ? "backspace" : modelData === "check" ? "check" : ""
            label: modelData === "backspace" || modelData === "check" ? "" : modelData
            iconSize: 24
            labelSize: 24
            vertical: false
            radius: 18
            background: root.theme.surfaceHigh
            borderColor: root.theme.outlineVariant
            foreground: root.theme.highText
            onClicked: {
                if (modelData === "backspace")
                    root.state.backspacePin();
                else if (modelData === "check")
                    root.state.unlock();
                else
                    root.digitPressed(modelData);
            }
        }
    }
}
