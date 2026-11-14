// Home-surface summary that opens the notification centre.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Theme theme
    required property ShellState state
    property bool landscape: false
    signal clicked()

    implicitHeight: Math.max(root.theme.minTouchTarget,
        (landscape ? 82 : 92) + Math.max(0, root.theme.scaledFont(15) - 15))
    scale: tap.pressed ? 0.985 : 1.0
    objectName: "padilha-touch-target"
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Notifications"
    Accessible.onPressAction: root.clicked()

    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()

    Behavior on scale {
        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: root.theme.surfaceContainer
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? root.theme.accent : root.theme.outlineVariant

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 16
                color: root.theme.primaryContainer
                Icon {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    name: "bell"
                    color: root.theme.primaryContainerText
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 2
                Row {
                    spacing: 8
                    Text {
                        text: "Notifications"
                        color: root.theme.containerText
                        font.pixelSize: root.theme.scaledFont(15)
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        visible: root.state.notificationCount > 0
                        width: Math.max(20, countLabel.implicitWidth + 10)
                        height: Math.max(20, root.theme.scaledFont(11) + 8)
                        radius: height / 2
                        color: root.theme.danger
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: root.state.notificationCount
                            color: root.theme.dangerText
                            font.pixelSize: root.theme.scaledFont(11)
                            font.weight: Font.Bold
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: root.state.notificationCount === 0
                        ? "All caught up"
                        : root.state.notifications[0].summary.length > 0
                            ? root.state.notifications[0].summary + " · " + root.state.notifications[0].body
                            : root.state.notifications[0].body
                    color: root.theme.containerMuted
                    font.pixelSize: root.theme.scaledFont(13)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Icon {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                name: "chevron_right"
                color: root.theme.containerMuted
            }
        }
    }

    TapHandler {
        id: tap
        onTapped: root.clicked()
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
}
