// Transient message shown above the navigation surface.

import QtQuick

Item {
    id: root

    required property Theme theme
    required property ShellState state
    property bool landscape: false
    signal clicked()

    width: Math.min(parent ? parent.width - 40 : 600, 620)
    height: 52
    opacity: root.state.toastVisible ? 1.0 : 0.0
    visible: opacity > 0.01
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    anchors.bottomMargin: root.landscape ? 22 : 102

    Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: root.theme.inverseSurface
        border.width: 1
        border.color: root.theme.outlineVariant
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 10

        Icon {
            width: 18
            height: 18
            name: "bell"
            color: root.theme.inverseText
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            width: parent.width - 30
            text: root.state.toastMessage
            color: root.theme.inverseText
            font.pixelSize: 13
            elide: Text.ElideRight
            maximumLineCount: 1
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    TapHandler {
        onTapped: root.clicked()
    }
}
