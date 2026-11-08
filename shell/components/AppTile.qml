// One app in the grid. Uses the app's icon when available and a palette-toned
// initial tile otherwise, so the grid still works in a minimal QEMU guest.

import QtQuick
import Quickshell

Item {
    id: root

    required property Theme theme
    required property var app
    property int tone: 0
    property bool showLabel: true
    property real tileSize: 72
    signal clicked()

    implicitWidth: tileSize
    implicitHeight: tileSize + (showLabel ? 30 : 0)
    scale: tap.pressed ? 0.95 : 1.0

    Accessible.role: Accessible.Button
    Accessible.name: app ? app.name : ""
    Accessible.onPressAction: root.clicked()

    readonly property color toneBackground: {
        switch (tone % 4) {
        case 1: return theme.secondaryContainer;
        case 2: return theme.tertiaryContainer;
        case 3: return theme.surfaceHigh;
        default: return theme.primaryContainer;
        }
    }
    readonly property color toneForeground: {
        switch (tone % 4) {
        case 1: return theme.secondaryContainerText;
        case 2: return theme.tertiaryContainerText;
        case 3: return theme.highText;
        default: return theme.primaryContainerText;
        }
    }

    Behavior on scale {
        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: tile
        width: root.tileSize
        height: root.tileSize
        radius: Math.round(root.tileSize * 0.28)
        color: root.toneBackground
        anchors.horizontalCenter: parent.horizontalCenter

        Image {
            id: appIcon
            anchors.centerIn: parent
            width: Math.round(root.tileSize * 0.5)
            height: width
            source: root.app && root.app.entry ? Quickshell.iconPath(root.app.icon) : ""
            sourceSize.width: width
            sourceSize.height: height
            fillMode: Image.PreserveAspectFit
            visible: source !== "" && status === Image.Ready
        }

        Text {
            anchors.centerIn: parent
            visible: !appIcon.visible
            text: root.app ? root.app.name.substring(0, 1).toUpperCase() : "?"
            color: root.toneForeground
            font.pixelSize: Math.round(root.tileSize * 0.38)
            font.weight: Font.DemiBold
        }
    }

    Text {
        visible: root.showLabel
        anchors.top: tile.bottom
        anchors.topMargin: 5
        width: parent.width
        text: root.app ? root.app.name : ""
        color: root.theme.text
        font.pixelSize: 12
        font.weight: Font.Medium
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    TapHandler {
        id: tap
        onTapped: root.clicked()
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
}
