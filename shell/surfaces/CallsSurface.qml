// Calls surface: ModemManager Voice calls with a large dial pad, incoming-call
// actions and graceful states for no modem, unavailable ModemManager, a locked
// SIM and modems without voice support.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    signal closed()

    readonly property var telephony: state.telephony
    readonly property int margin: landscape ? 28 : 22
    readonly property var visibleCalls: telephony.calls.filter(call => call.state !== "terminated")
    readonly property var ringingCall: {
        for (const call of root.visibleCalls) {
            if (call.state === "ringing_in" || call.state === "waiting")
                return call;
        }
        return null;
    }

    property string dialNumber: ""

    function appendDigit(digit) {
        if (root.dialNumber.length >= 32)
            return;
        root.dialNumber += String(digit);
    }

    function backspace() {
        root.dialNumber = root.dialNumber.substring(0, Math.max(0, root.dialNumber.length - 1));
    }

    function placeCall() {
        if (!root.telephony.canDial || root.dialNumber.trim().length === 0)
            return;
        root.telephony.dial(root.dialNumber);
        root.dialNumber = "";
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, content.implicitHeight + root.margin * 2)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: content
            x: Math.max(root.margin, (flick.width - width) / 2)
            y: root.margin
            width: Math.min(flick.width - root.margin * 2, root.landscape ? 620 : 10000)
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                TouchButton {
                    icon: "back"
                    vertical: false
                    iconSize: 22
                    background: root.theme.surfaceHigh
                    foreground: root.theme.text
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 16
                    onClicked: root.closed()
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "Calls"
                        color: root.theme.text
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.telephony.statusLabel
                        color: root.theme.textMuted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                TouchButton {
                    icon: "arrow_up"
                    vertical: false
                    iconSize: 20
                    background: root.theme.surfaceHigh
                    foreground: root.theme.text
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 16
                    onClicked: root.telephony.refresh()
                }
            }

            TelephonyStatusCard {
                Layout.fillWidth: true
                theme: root.theme
                telephony: root.telephony
                onRetryRequested: root.telephony.refresh()
            }

            Repeater {
                model: root.visibleCalls
                delegate: CallCard {
                    required property var modelData
                    Layout.fillWidth: true
                    theme: root.theme
                    call: modelData
                    onAnswerRequested: root.telephony.answer(modelData)
                    onHangupRequested: root.telephony.hangup(modelData)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.telephony.ready && root.visibleCalls.length === 0
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    radius: 20
                    color: root.theme.surfaceHigh
                    border.width: 1
                    border.color: root.dialNumber.length > 0
                        ? root.theme.accent : root.theme.outlineVariant

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: root.dialNumber.length > 0 ? root.dialNumber : "Enter a number"
                            color: root.dialNumber.length > 0 ? root.theme.highText : root.theme.highMuted
                            font.pixelSize: 28
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        TouchButton {
                            visible: root.dialNumber.length > 0
                            icon: "backspace"
                            iconSize: 22
                            implicitWidth: 52
                            implicitHeight: 52
                            radius: 16
                            background: root.theme.surfaceContainer
                            foreground: root.theme.highText
                            onClicked: root.backspace()
                        }
                    }
                }

                DialPad {
                    Layout.fillWidth: true
                    theme: root.theme
                    landscape: root.landscape
                    onDigitPressed: digit => root.appendDigit(digit)
                }

                TouchButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    icon: "phone"
                    label: "Call"
                    vertical: false
                    iconSize: 22
                    labelSize: 16
                    radius: 18
                    enabled: root.telephony.canDial && root.dialNumber.trim().length > 0
                    background: enabled ? root.theme.success : root.theme.surfaceHigh
                    foreground: enabled ? root.theme.successText : root.theme.textMuted
                    onClicked: root.placeCall()
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.telephony.emergencyOnly
                    text: "Emergency calls are not supported by this prototype."
                    color: root.theme.danger
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.telephony.ready
                spacing: 8

                Item { Layout.preferredHeight: 36 }

                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    width: 52
                    height: 52
                    name: root.telephony.modemPresent ? "signal" : "phone"
                    level: root.telephony.signalQuality >= 0 ? root.telephony.signalQuality / 100 : -1
                    color: root.theme.textMuted
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
