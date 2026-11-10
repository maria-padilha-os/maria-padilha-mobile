// One ModemManager call. The card handles ringing, dialing and active calls
// with the same 48 px minimum targets as the rest of the shell.

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property Theme theme
    required property var call
    property bool demo: false

    signal answerRequested()
    signal hangupRequested()

    readonly property bool ringing: call && (call.state === "ringing_in" || call.state === "waiting")
    readonly property string directionLabel: {
        if (!call)
            return "";
        if (root.ringing)
            return "Incoming call";
        if (call.direction === "outgoing")
            return "Outgoing call";
        return "Call";
    }

    implicitHeight: cardLayout.implicitHeight + 26
    radius: 20
    color: root.ringing ? root.theme.primaryContainer : root.theme.surfaceContainer
    border.width: 1
    border.color: root.ringing ? root.theme.primary : root.theme.outlineVariant

    ColumnLayout {
        id: cardLayout
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 16
                color: root.ringing ? root.theme.primary : root.theme.surfaceHigh
                Icon {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    name: "phone"
                    color: root.ringing ? root.theme.primaryText : root.theme.text
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: root.call ? root.call.number : ""
                    color: root.ringing ? root.theme.primaryContainerText : root.theme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: root.directionLabel + (root.call && root.call.multiparty ? " · conference" : "")
                    color: root.ringing ? root.theme.primaryContainerText : root.theme.textMuted
                    font.pixelSize: 12
                }
            }

            Rectangle {
                implicitWidth: stateText.implicitWidth + 18
                implicitHeight: 30
                radius: 15
                color: root.ringing ? root.theme.primary : root.theme.surfaceHigh
                Text {
                    id: stateText
                    anchors.centerIn: parent
                    text: root.call ? (root.call.stateLabel || root.call.state) : ""
                    color: root.ringing ? root.theme.primaryText : root.theme.highText
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            TouchButton {
                visible: root.ringing
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                icon: "phone"
                label: "Answer"
                vertical: false
                iconSize: 20
                labelSize: 14
                radius: 16
                background: root.theme.success
                foreground: root.theme.successText
                onClicked: root.answerRequested()
            }

            TouchButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                icon: "close"
                label: root.ringing ? "Decline" : "Hang up"
                vertical: false
                iconSize: 20
                labelSize: 14
                radius: 16
                background: root.theme.danger
                foreground: root.theme.dangerText
                onClicked: root.hangupRequested()
            }
        }
    }
}
