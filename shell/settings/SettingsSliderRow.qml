// Touch-friendly slider row. The 44 px track area is the gesture target and
// the whole row is at least 72 px high, matching the desktop SliderRow layout.

import QtQuick
import QtQuick.Layouts
import "../components"

SettingsRowCard {
    id: root

    property string icon: ""
    property string label: ""
    property string description: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property string valueLabel: ""
    property bool enabled: true
    signal moved(real value)

    Layout.fillWidth: true
    implicitHeight: 78
    opacity: root.enabled ? 1 : 0.55

    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    Accessible.description: root.description

    function _ratio() {
        const span = root.to - root.from;
        if (!(span > 0))
            return 0;
        return Math.max(0, Math.min(1, (root.value - root.from) / span));
    }

    function _emitAt(x) {
        if (!root.enabled || track.width <= 0)
            return;
        const ratio = Math.max(0, Math.min(1, x / track.width));
        const raw = root.from + ratio * (root.to - root.from);
        const step = root.stepSize > 0 ? root.stepSize : 0.01;
        const stepped = Math.round(raw / step) * step;
        const next = Math.max(root.from, Math.min(root.to, stepped));
        if (Math.abs(next - root.value) >= step / 2)
            root.moved(next);
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 10
        anchors.bottomMargin: 8
        spacing: 12

        Icon {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignTop
            name: root.icon
            visible: root.icon.length > 0
            color: root.theme.highMuted
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.label
                    color: root.theme.highText
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    text: root.valueLabel.length > 0
                        ? root.valueLabel
                        : Math.round(root.value * 100) + "%"
                    color: root.theme.highMuted
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                color: root.theme.highMuted
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Item {
                id: sliderArea
                Layout.fillWidth: true
                Layout.preferredHeight: 44

                Rectangle {
                    id: track
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 10
                    radius: 5
                    color: root.theme.surfaceHighest

                    Rectangle {
                        width: Math.max(0, Math.min(parent.width, parent.width * root._ratio()))
                        height: parent.height
                        radius: parent.radius
                        color: root.enabled ? root.theme.primary : root.theme.outline
                    }

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        y: (parent.height - height) / 2
                        x: Math.max(0, Math.min(parent.width - width,
                            parent.width * root._ratio() - width / 2))
                        color: root.enabled ? root.theme.primaryText : root.theme.surfaceHigh
                        border.width: 2
                        border.color: root.enabled ? root.theme.primary : root.theme.outline
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.enabled
                    preventStealing: true
                    onPressed: mouse => root._emitAt(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed)
                            root._emitAt(mouse.x);
                    }
                }
            }
        }
    }
}
