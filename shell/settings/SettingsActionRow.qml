// Large tap target for a row that opens another page or performs an action.

import QtQuick
import QtQuick.Layouts
import "../components"

SettingsRowCard {
    id: root

    property string icon: ""
    property string label: ""
    property string description: ""
    property string trailingIcon: "chevron_right"
    property bool enabled: true
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 64
    interactive: root.enabled
    opacity: root.enabled ? 1 : 0.55

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.description
    Accessible.onPressAction: if (root.enabled) root.clicked()

    TapHandler {
        enabled: root.enabled
        onTapped: root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 14
        spacing: 12

        Icon {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
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
                elide: Text.ElideRight
            }
        }

        Icon {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            name: root.trailingIcon
            color: root.theme.highMuted
        }
    }
}
