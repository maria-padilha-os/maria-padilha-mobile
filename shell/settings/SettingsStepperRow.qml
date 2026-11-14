// Numeric stepper with 48 px minus/plus targets, adapted from the desktop
// Nexus StepperRow. Emits moved(next) and leaves ownership to the caller.

import QtQuick
import QtQuick.Layouts
import "../components"

SettingsRowCard {
    id: root
    property string label: ""
    property string description: ""
    property real value: 0
    property real from: 0
    property real to: 99
    property real stepSize: 1
    property string valueSuffix: ""
    property bool enabled: true
    signal moved(real value)

    Layout.fillWidth: true
    implicitHeight: 72
    opacity: root.enabled ? 1 : 0.55

    Accessible.role: Accessible.SpinBox
    Accessible.name: root.label
    Accessible.description: root.description

    function _step(delta) {
        if (!root.enabled)
            return;
        const next = Math.max(root.from, Math.min(root.to, root.value + delta));
        if (Math.abs(next - root.value) > 0.0001)
            root.moved(next);
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 10
        spacing: 8

        Column {
            Layout.fillWidth: true
            spacing: 1

            Text {
                width: parent.width
                text: root.label
                color: root.theme.highText
                font.pixelSize: root.theme.scaledFont(16)
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.description.length > 0
                text: root.description
                color: root.theme.highMuted
                font.pixelSize: root.theme.scaledFont(12)
                elide: Text.ElideRight
            }
        }

        TouchButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            theme: root.theme
            label: "−"
            labelSize: 24
            vertical: true
            enabled: root.enabled && root.value > root.from
            background: root.theme.surfaceContainer
            foreground: root.theme.highText
            radius: 14
            onClicked: root._step(-root.stepSize)
        }

        Text {
            Layout.preferredWidth: 58
            text: Math.round(root.value) + root.valueSuffix
            color: root.theme.highText
            font.pixelSize: root.theme.scaledFont(17)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }

        TouchButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            theme: root.theme
            label: "+"
            labelSize: 24
            vertical: true
            enabled: root.enabled && root.value < root.to
            background: root.theme.surfaceContainer
            foreground: root.theme.highText
            radius: 14
            onClicked: root._step(root.stepSize)
        }
    }
}
