// One SMS from ModemManager's Messaging interface. Message text is displayed
// in memory only; this component never logs or persists it.

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property Theme theme
    required property var message
    property bool demo: false

    signal replyRequested()
    signal deleteRequested()

    readonly property bool incoming: message && message.direction === "incoming"

    implicitHeight: cardLayout.implicitHeight + 24
    radius: 18
    color: root.incoming ? root.theme.surfaceContainer : root.theme.surfaceHigh
    border.width: 1
    border.color: root.incoming ? root.theme.outlineVariant : root.theme.outline

    ColumnLayout {
        id: cardLayout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Icon {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                name: root.incoming ? "message" : "send"
                color: root.incoming ? root.theme.accent : root.theme.success
            }

            Text {
                Layout.fillWidth: true
                text: (root.incoming ? "From " : "To ") + (root.message ? root.message.number : "")
                color: root.theme.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                text: root.message ? (root.message.stateLabel || root.message.state) : ""
                color: root.theme.textMuted
                font.pixelSize: 11
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.message ? root.message.text : ""
            color: root.theme.containerText
            font.pixelSize: 14
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: {
                    if (!root.message || !root.message.timestamp)
                        return "";
                    return String(root.message.timestamp).replace("T", " ").substring(0, 16);
                }
                color: root.theme.textMuted
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            TouchButton {
                icon: "message"
                label: "Reply"
                vertical: false
                iconSize: 16
                labelSize: 11
                implicitHeight: 48
                foreground: root.theme.accent
                onClicked: root.replyRequested()
            }

            TouchButton {
                icon: "delete"
                iconSize: 17
                implicitWidth: 48
                implicitHeight: 48
                radius: 14
                foreground: root.theme.danger
                background: root.theme.surfaceContainer
                onClicked: root.deleteRequested()
            }
        }
    }
}
