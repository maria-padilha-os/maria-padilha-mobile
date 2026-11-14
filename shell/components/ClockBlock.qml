// Responsive clock used on the home and lock surfaces.

import QtQuick
import Quickshell

Item {
    id: root

    required property Theme theme
    property int timeSize: 96
    property bool showBrand: true
    property bool centered: true

    implicitHeight: content.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        id: content
        width: parent.width
        spacing: 2
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: Qt.formatTime(clock.date, "HH:mm")
            color: root.theme.text
            font.pixelSize: root.theme.scaledFont(root.timeSize)
            font.weight: Font.Light
            horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
        }
        Text {
            width: parent.width
            text: Qt.formatDate(clock.date, "dddd d MMMM")
            color: root.theme.textMuted
            font.pixelSize: root.theme.scaledFont(Math.max(14, Math.round(root.timeSize * 0.19)))
            horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
        }
        Text {
            visible: root.showBrand
            width: parent.width
            text: "Maria Padilha"
            color: root.theme.accent
            font.pixelSize: root.theme.scaledFont(Math.max(11, Math.round(root.timeSize * 0.13)))
            font.letterSpacing: 1.2
            font.weight: Font.Medium
            horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
        }
    }
}
