// Touch-friendly toggle row. The caller owns the value: the row only emits
// toggled(next), so a binding to the settings store is never broken locally.

import QtQuick
import QtQuick.Layouts
import "../components"

SettingsRowCard {
    id: root

    property string icon: ""
    property string label: ""
    property string description: ""
    property bool checked: false
    property bool enabled: true
    signal toggled(bool checked)

    Layout.fillWidth: true
    implicitHeight: 68
    interactive: root.enabled
    opacity: root.enabled ? 1 : 0.55

    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.description: root.description
    Accessible.checked: root.checked
    Accessible.onPressAction: if (root.enabled) root.toggled(!root.checked)

    function _activate() {
        if (root.enabled)
            root.toggled(!root.checked);
    }

    TapHandler {
        enabled: root.enabled
        onTapped: root._activate()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        spacing: 12

        Icon {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            name: root.icon
            visible: root.icon.length > 0
            color: root.checked ? root.theme.accent : root.theme.highMuted
        }

        Column {
            Layout.fillWidth: true
            spacing: 2

            Text {
                width: parent.width
                text: root.label
                color: root.theme.highText
                font.pixelSize: 16
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.description.length > 0
                text: root.description
                color: root.theme.highMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.preferredWidth: 58
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignVCenter
            radius: 18
            color: root.checked ? root.theme.primary : root.theme.surfaceHighest
            border.width: 1
            border.color: root.checked ? root.theme.primary : root.theme.outlineVariant

            Rectangle {
                width: 28
                height: 28
                radius: 14
                y: 3
                x: root.checked ? parent.width - width - 4 : 4
                color: root.checked ? root.theme.primaryText : root.theme.highText

                Behavior on x {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
