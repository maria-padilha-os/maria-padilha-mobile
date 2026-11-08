// Touch-first button: 48 px minimum target, 56–72 px in the shell, with a
// pressed-state scale and optional icon + label.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string icon: ""
    property string label: ""
    property color foreground: "#201a18"
    property color background: "transparent"
    property color borderColor: "transparent"
    property color activeBackground: background
    property color activeForeground: foreground
    property bool active: false
    property bool enabled: true
    property bool vertical: true
    property int iconSize: 24
    property real radius: 18
    property int labelSize: 12
    property int horizontalPadding: 12
    property int verticalPadding: 8
    signal clicked()
    signal longPressed()

    readonly property real _textWidth: label.length > 0 ? label.length * labelSize * 0.58 + 8 : 0
    implicitWidth: vertical
        ? Math.max(48, Math.max(iconSize, _textWidth) + horizontalPadding * 2)
        : Math.max(48, iconSize + _textWidth + horizontalPadding * 2)
    implicitHeight: vertical ? iconSize + (label.length > 0 ? labelSize + 8 : 0) + verticalPadding * 2 : 48
    opacity: enabled ? 1.0 : 0.45
    scale: tap.pressed ? 0.96 : 1.0

    Accessible.role: Accessible.Button
    Accessible.name: label.length > 0 ? label : icon
    Accessible.onPressAction: if (enabled) root.clicked()

    Behavior on scale {
        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.active ? root.activeBackground : root.background
        border.width: root.borderColor.a > 0 ? 1 : 0
        border.color: root.borderColor
    }

    Loader {
        sourceComponent: root.vertical ? verticalContent : horizontalContent
        anchors.centerIn: parent
    }

    Component {
        id: verticalContent
        Column {
            spacing: 4
            Icon {
                width: root.iconSize
                height: root.iconSize
                name: root.icon
                visible: root.icon.length > 0
                color: root.active ? root.activeForeground : root.foreground
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                visible: root.label.length > 0
                text: root.label
                color: root.active ? root.activeForeground : root.foreground
                font.pixelSize: root.labelSize
                font.weight: Font.Medium
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Component {
        id: horizontalContent
        Row {
            spacing: 8
            Icon {
                width: root.iconSize
                height: root.iconSize
                name: root.icon
                visible: root.icon.length > 0
                color: root.active ? root.activeForeground : root.foreground
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: root.label.length > 0
                text: root.label
                color: root.active ? root.activeForeground : root.foreground
                font.pixelSize: root.labelSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    TapHandler {
        id: tap
        enabled: root.enabled
        onTapped: root.clicked()
        onLongPressed: root.longPressed()
    }

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
