// Touch-first button: a theme-enforced minimum target (48px by default),
// scalable label text and optional icon + label. Keyboard focus uses the same
// path as touch so Space/Enter activate the control.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Theme theme
    property string icon: ""
    property string label: ""
    property string accessibleName: ""
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

    readonly property bool hasLabel: label.length > 0
    readonly property int scaledLabelSize: root.theme.scaledFont(root.labelSize)
    readonly property real _textWidth: hasLabel ? label.length * scaledLabelSize * 0.58 + 8 : 0
    implicitWidth: vertical
        ? Math.max(root.theme.minTouchTarget, Math.max(iconSize, _textWidth) + horizontalPadding * 2)
        : Math.max(root.theme.minTouchTarget, iconSize + _textWidth + horizontalPadding * 2)
    implicitHeight: Math.max(root.theme.minTouchTarget,
        vertical ? iconSize + (hasLabel ? scaledLabelSize + 8 : 0) + verticalPadding * 2
                 : Math.max(iconSize, scaledLabelSize) + verticalPadding * 2)
    opacity: enabled ? 1.0 : 0.45
    scale: tap.pressed ? 0.96 : 1.0
    objectName: "padilha-touch-target"
    activeFocusOnTab: enabled

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName.length > 0 ? accessibleName : (hasLabel ? label : icon)
    Accessible.onPressAction: if (enabled) root.clicked()

    Keys.onReturnPressed: if (root.enabled) root.clicked()
    Keys.onEnterPressed: if (root.enabled) root.clicked()
    Keys.onSpacePressed: if (root.enabled) root.clicked()

    Behavior on scale {
        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.active ? root.activeBackground : root.background
        border.width: root.activeFocus ? 2 : (root.borderColor.a > 0 ? 1 : 0)
        border.color: root.activeFocus ? root.theme.accent : root.borderColor
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
                visible: root.hasLabel
                text: root.label
                color: root.active ? root.activeForeground : root.foreground
                font.pixelSize: root.theme.scaledFont(root.labelSize)
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
                visible: root.hasLabel
                text: root.label
                color: root.active ? root.activeForeground : root.foreground
                font.pixelSize: root.theme.scaledFont(root.labelSize)
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
