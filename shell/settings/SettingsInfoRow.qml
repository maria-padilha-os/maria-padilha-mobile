// Read-only label/value row, adapted from the desktop Nexus InfoRow.

import QtQuick
import QtQuick.Layouts
import "../components"

SettingsRowCard {
    id: root

    property string icon: ""
    property string label: ""
    property string description: ""
    property string value: ""

    Layout.fillWidth: true
    implicitHeight: Math.max(60, valueText.implicitHeight + 24)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        Icon {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            name: root.icon
            visible: root.icon.length > 0
            color: root.theme.highMuted
        }

        Column {
            Layout.fillWidth: true
            spacing: 1

            Text {
                width: parent.width
                text: root.label
                color: root.theme.highText
                font.pixelSize: root.theme.scaledFont(15)
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.description.length > 0
                text: root.description
                color: root.theme.highMuted
                font.pixelSize: root.theme.scaledFont(11)
                elide: Text.ElideRight
            }
        }

        Text {
            id: valueText
            Layout.maximumWidth: parent.width * 0.46
            text: root.value
            color: root.theme.highMuted
            font.pixelSize: root.theme.scaledFont(14)
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.WordWrap
        }
    }
}
