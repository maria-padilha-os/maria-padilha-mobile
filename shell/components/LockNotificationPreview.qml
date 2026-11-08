// Privacy-safe lock preview: counts only, never notification bodies.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Theme theme
    required property ShellState state
    implicitHeight: 74
    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: root.theme.surfaceContainer
        border.width: 1
        border.color: root.theme.outlineVariant

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 14
                color: root.theme.primaryContainer
                Icon {
                    anchors.centerIn: parent
                    width: 21
                    height: 21
                    name: "bell"
                    color: root.theme.primaryContainerText
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: root.state.notificationCount === 0
                        ? "No notifications"
                        : root.state.notificationCount + (root.state.notificationCount === 1 ? " notification waiting" : " notifications waiting")
                    color: root.theme.containerText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Unlock to view"
                    color: root.theme.containerMuted
                    font.pixelSize: 12
                }
            }

            Icon {
                Layout.preferredWidth: 17
                Layout.preferredHeight: 17
                name: "chevron_right"
                color: root.theme.containerMuted
            }
        }
    }

    TapHandler {
        onTapped: {
            root.clicked();
            root.state.toast("Unlock to view notifications");
        }
    }
}
