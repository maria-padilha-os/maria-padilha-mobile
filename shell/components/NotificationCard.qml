// One notification card with a large dismiss target.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property var notification
    signal dismissed()

    implicitHeight: cardContent.implicitHeight + 28

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: root.theme.surfaceContainer
        border.width: 1
        border.color: root.theme.outlineVariant
    }

    RowLayout {
        id: cardContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignTop
            radius: 15
            color: root.notification.urgency === 2 ? root.theme.dangerContainer : root.theme.primaryContainer
            Text {
                anchors.centerIn: parent
                text: (root.notification.appName || "?").substring(0, 1).toUpperCase()
                color: root.notification.urgency === 2 ? root.theme.dangerContainerText : root.theme.primaryContainerText
                font.pixelSize: root.theme.scaledFont(18)
                font.weight: Font.DemiBold
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: root.notification.appName
                    color: root.theme.containerText
                    font.pixelSize: root.theme.scaledFont(13)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    text: root.state.relativeTime(root.notification.time)
                    color: root.theme.containerMuted
                    font.pixelSize: root.theme.scaledFont(11)
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.notification.summary.length > 0
                text: root.notification.summary
                color: root.theme.containerText
                font.pixelSize: root.theme.scaledFont(15)
                font.weight: Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: root.notification.body
                color: root.theme.containerMuted
                font.pixelSize: root.theme.scaledFont(13)
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }

        TouchButton {
            theme: root.theme
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignTop
            icon: "close"
            accessibleName: "Dismiss notification"
            iconSize: 18
            radius: 14
            background: root.theme.surfaceHigh
            foreground: root.theme.highMuted
            onClicked: root.dismissed()
        }
    }
}
