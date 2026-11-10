// SMS surface: received and sent messages from ModemManager's Messaging
// interface, with a compose field. Message text stays in memory; it is never
// written to a log or a local cache. ModemManager's on-modem storage remains
// the source of truth for messages the modem keeps.

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
    readonly property int cardWidth: Math.min(width - margin * 2, landscape ? 760 : 10000)

    property string recipient: ""
    property string body: ""

    function replyTo(message) {
        if (!message)
            return;
        root.recipient = message.number;
        toInput.text = message.number;
        bodyInput.forceActiveFocus();
    }

    function send() {
        if (!root.telephony.canMessage)
            return;
        if (root.telephony.sendSms(root.recipient, root.body)) {
            root.body = "";
            bodyInput.text = "";
            bodyInput.forceActiveFocus();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.margin
        spacing: 12

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
                    text: "Messages"
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

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.cardWidth
                height: parent.height
                model: root.telephony.messages
                spacing: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: SmsCard {
                    required property var modelData
                    width: list.width
                    theme: root.theme
                    message: modelData
                    onReplyRequested: root.replyTo(modelData)
                    onDeleteRequested: root.telephony.deleteMessage(modelData)
                }
            }

            Column {
                visible: root.telephony.canMessage && root.telephony.messages.length === 0
                anchors.centerIn: parent
                spacing: 10
                Icon {
                    width: 42
                    height: 42
                    name: "message"
                    color: root.theme.textMuted
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "No messages"
                    color: root.theme.text
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Received SMS will appear here."
                    color: root.theme.textMuted
                    font.pixelSize: 13
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Icon {
                visible: !root.telephony.canMessage
                width: 48
                height: 48
                name: root.telephony.modemPresent ? "message" : "warning"
                color: root.theme.textMuted
                anchors.centerIn: parent
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.cardWidth
            Layout.preferredHeight: compose.implicitHeight + 20
            visible: root.telephony.canMessage
            radius: 18
            color: root.theme.surfaceContainer
            border.width: 1
            border.color: root.theme.outlineVariant

            ColumnLayout {
                id: compose
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: 12
                    color: root.theme.surfaceHigh
                    border.width: 1
                    border.color: toInput.activeFocus ? root.theme.accent : root.theme.outlineVariant

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8
                        Text {
                            text: "To"
                            color: root.theme.textMuted
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        TextInput {
                            id: toInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.theme.highText
                            selectionColor: root.theme.primaryContainer
                            selectedTextColor: root.theme.primaryContainerText
                            font.pixelSize: 15
                            inputMethodHints: Qt.ImhDialableCharactersOnly | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            onTextChanged: root.recipient = text
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    root.state.attachKeyboard(toInput, "text");
                                else
                                    root.state.detachKeyboard(toInput);
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: 12
                        color: root.theme.surfaceHigh
                        border.width: 1
                        border.color: bodyInput.activeFocus ? root.theme.accent : root.theme.outlineVariant

                        TextInput {
                            id: bodyInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.theme.highText
                            selectionColor: root.theme.primaryContainer
                            selectedTextColor: root.theme.primaryContainerText
                            font.pixelSize: 15
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            onTextChanged: root.body = text
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    root.state.attachKeyboard(bodyInput, "text");
                                else
                                    root.state.detachKeyboard(bodyInput);
                            }
                            onAccepted: root.send()
                            Keys.onEscapePressed: root.closed()
                        }
                    }

                    TouchButton {
                        icon: "send"
                        iconSize: 19
                        implicitWidth: 50
                        implicitHeight: 50
                        radius: 15
                        enabled: root.telephony.canMessage &&
                                root.recipient.trim().length > 0 && root.body.length > 0
                        background: enabled ? root.theme.primary : root.theme.surfaceHigh
                        foreground: enabled ? root.theme.primaryText : root.theme.textMuted
                        onClicked: root.send()
                    }
                }
            }
        }
    }

    Connections {
        target: root.telephony
        function onMessagesChanged() {
            if (list.count > 0)
                list.positionViewAtEnd();
        }
    }
}
