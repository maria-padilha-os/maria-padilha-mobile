// Lock surface. This is a UI prototype: any four digits unlock and no PAM,
// device daemon or real authentication path is involved.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    readonly property int margin: landscape ? 28 : 26

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.theme.surface }
            GradientStop { position: 1.0; color: root.theme.surfaceLow }
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.landscape ? landscapeLayout : portraitLayout
    }

    Component {
        id: portraitLayout

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.margin
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 15
                    color: root.theme.primaryContainer
                    Icon {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        name: "lock"
                        color: root.theme.primaryContainerText
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "Maria Padilha"
                        color: root.theme.accent
                        font.pixelSize: root.theme.scaledFont(13)
                        font.letterSpacing: 1.1
                        font.weight: Font.Medium
                    }
                    Text {
                        text: "Locked"
                        color: root.theme.textMuted
                        font.pixelSize: root.theme.scaledFont(12)
                    }
                }

                LockStatusPill {
                    theme: root.theme
                    state: root.state
                }
            }

            Item { Layout.fillHeight: true }

            ClockBlock {
                Layout.fillWidth: true
                theme: root.theme
                timeSize: 92
                showBrand: false
            }

            Item { Layout.fillHeight: true }

            LockNotificationPreview {
                Layout.fillWidth: true
                theme: root.theme
                state: root.state
            }

            PinDots {
                Layout.alignment: Qt.AlignHCenter
                theme: root.theme
                state: root.state
            }

            Text {
                Layout.fillWidth: true
                text: "Prototype lock · any four digits unlock"
                color: root.theme.textMuted
                font.pixelSize: root.theme.scaledFont(12)
                horizontalAlignment: Text.AlignHCenter
            }

            PinPad {
                Layout.fillWidth: true
                theme: root.theme
                state: root.state
                onDigitPressed: root.state.appendPin(digit)
            }

            TouchButton {
                theme: root.theme
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                icon: "unlock"
                label: "Unlock"
                vertical: false
                iconSize: 21
                labelSize: 15
                radius: 18
                enabled: root.state.pin.length === 4
                background: enabled ? root.theme.primary : root.theme.surfaceHigh
                foreground: enabled ? root.theme.primaryText : root.theme.textMuted
                onClicked: root.state.unlock()
            }
        }
    }

    Component {
        id: landscapeLayout

        RowLayout {
            anchors.fill: parent
            anchors.margins: root.margin
            spacing: 36

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 520
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 15
                        color: root.theme.primaryContainer
                        Icon {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            name: "lock"
                            color: root.theme.primaryContainerText
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: "Maria Padilha"
                            color: root.theme.accent
                            font.pixelSize: root.theme.scaledFont(13)
                            font.letterSpacing: 1.1
                            font.weight: Font.Medium
                        }
                        Text {
                            text: "Locked"
                            color: root.theme.textMuted
                            font.pixelSize: root.theme.scaledFont(12)
                        }
                    }
                    LockStatusPill {
                    theme: root.theme
                    state: root.state
                }
                }

                ClockBlock {
                    Layout.fillWidth: true
                    theme: root.theme
                    timeSize: 74
                    showBrand: false
                    centered: false
                }

                LockNotificationPreview {
                    Layout.fillWidth: true
                    theme: root.theme
                    state: root.state
                }

                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                Layout.preferredWidth: 430
                Layout.maximumWidth: 470
                spacing: 12

                PinDots {
                    Layout.alignment: Qt.AlignHCenter
                    theme: root.theme
                    state: root.state
                }

                Text {
                    Layout.fillWidth: true
                    text: "Prototype lock · any four digits unlock"
                    color: root.theme.textMuted
                    font.pixelSize: root.theme.scaledFont(12)
                    horizontalAlignment: Text.AlignHCenter
                }

                PinPad {
                    Layout.fillWidth: true
                    theme: root.theme
                    state: root.state
                    landscape: true
                    onDigitPressed: root.state.appendPin(digit)
                }

                TouchButton {
                    theme: root.theme
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    icon: "unlock"
                    label: "Unlock"
                    vertical: false
                    iconSize: 21
                    labelSize: 15
                    radius: 18
                    enabled: root.state.pin.length === 4
                    background: enabled ? root.theme.primary : root.theme.surfaceHigh
                    foreground: enabled ? root.theme.primaryText : root.theme.textMuted
                    onClicked: root.state.unlock()
                }
            }
        }
    }


}
