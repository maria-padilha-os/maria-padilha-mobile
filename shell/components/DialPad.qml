// Large numeric dial pad. The digits are strings so the Calls surface can
// validate and pass them to ModemManager unchanged.

import QtQuick
import QtQuick.Layouts

GridLayout {
    id: root

    required property Theme theme
    property bool landscape: false
    property int keyHeight: root.theme.touchTarget(Math.max(landscape ? 54 : 62,
        root.theme.scaledFont(23) + 16))
    signal digitPressed(string digit)

    columns: 3
    rowSpacing: 8
    columnSpacing: 8

    Repeater {
        model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

        delegate: TouchButton {
            required property string modelData
            theme: root.theme
            Layout.fillWidth: true
            Layout.preferredHeight: root.keyHeight
            label: modelData
            labelSize: 23
            vertical: false
            radius: 18
            background: root.theme.surfaceHigh
            borderColor: root.theme.outlineVariant
            foreground: root.theme.highText
            onClicked: root.digitPressed(modelData)
        }
    }
}
