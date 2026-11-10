// Compact cellular status card shared by the calls and messages surfaces.
// A missing modem, a stopped ModemManager and a locked SIM all render here
// instead of being treated as fatal errors.

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property Theme theme
    required property var telephony

    signal retryRequested()

    implicitHeight: content.implicitHeight + 26
    radius: 18
    color: root.telephony.ready ? root.theme.surfaceContainer : root.theme.surfaceHigh
    border.width: 1
    border.color: root.telephony.ready ? root.theme.outlineVariant
        : (root.telephony.state === "failed" || root.telephony.state === "locked"
            ? root.theme.danger : root.theme.outline)

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            Layout.alignment: Qt.AlignTop
            radius: 14
            color: root.telephony.ready ? root.theme.primaryContainer : root.theme.surfaceHighest
            Icon {
                anchors.centerIn: parent
                width: 22
                height: 22
                name: root.telephony.modemPresent ? "signal" : "warning"
                level: root.telephony.signalQuality >= 0 ? root.telephony.signalQuality / 100 : -1
                color: root.telephony.ready ? root.theme.primaryContainerText : root.theme.textMuted
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
                    text: root.telephony.statusLabel
                    color: root.theme.text
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    visible: root.telephony.ready && root.telephony.signalQuality >= 0
                    text: root.telephony.signalQuality + "%"
                    color: root.theme.textMuted
                    font.pixelSize: 11
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.telephony.statusDetail
                color: root.theme.textMuted
                font.pixelSize: 12
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Text {
                visible: root.telephony.lastError.length > 0
                Layout.fillWidth: true
                text: "Last operation: " + root.telephony.lastError
                color: root.theme.danger
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        TouchButton {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignTop
            icon: "arrow_up"
            iconSize: 18
            radius: 14
            background: root.theme.surfaceContainer
            foreground: root.theme.text
            onClicked: root.retryRequested()
        }
    }
}
