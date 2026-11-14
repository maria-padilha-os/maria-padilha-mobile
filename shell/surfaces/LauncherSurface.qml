// Searchable app grid. Portrait uses four columns; landscape uses six.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape
    signal closed()
    signal appLaunched(var app)

    readonly property int margin: landscape ? 28 : 22
    readonly property int columns: landscape ? 6 : 4

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.margin
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            TouchButton {
                theme: root.theme
                icon: "back"
                accessibleName: "Back"
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
                    text: "Apps"
                    color: root.theme.text
                    font.pixelSize: root.theme.scaledFont(24)
                    font.weight: Font.DemiBold
                }
                Text {
                    text: root.state.filteredApps.length + " available"
                    color: root.theme.textMuted
                    font.pixelSize: root.theme.scaledFont(12)
                }
            }

            Rectangle {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: 16
                color: root.theme.surfaceHigh
                Icon {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    name: "grid"
                    color: root.theme.text
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            radius: 18
            color: root.theme.surfaceHigh
            border.width: 1
            border.color: input.activeFocus ? root.theme.accent : root.theme.outlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 8
                spacing: 10

                Icon {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    name: "search"
                    color: root.theme.highMuted
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextInput {
                        id: input
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.highText
                        selectionColor: root.theme.primaryContainer
                        selectedTextColor: root.theme.primaryContainerText
                        font.pixelSize: root.theme.scaledFont(17)
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        onTextChanged: root.state.appQuery = text
                        onActiveFocusChanged: {
                            if (activeFocus)
                                root.state.attachKeyboard(input, "text");
                            else
                                root.state.detachKeyboard(input);
                        }
                        onAccepted: {
                            if (root.state.filteredApps.length > 0)
                                root.appLaunched(root.state.filteredApps[0]);
                        }
                        Keys.onEscapePressed: root.closed()
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text.length === 0
                        text: "Search apps"
                        color: root.theme.highMuted
                        font.pixelSize: root.theme.scaledFont(17)
                    }
                }

                TouchButton {
                    theme: root.theme
                    visible: input.text.length > 0
                    icon: "close"
                    accessibleName: "Clear search"
                    iconSize: 17
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 24
                    background: root.theme.surfaceContainer
                    foreground: root.theme.highText
                    onClicked: {
                        input.text = "";
                        input.forceActiveFocus();
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: grid
                anchors.fill: parent
                cellWidth: width / root.columns
                cellHeight: cellWidth + 8
                model: root.state.filteredApps.length
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flow: GridView.FlowLeftToRight
                reuseItems: true

                delegate: Item {
                    required property int index

                    width: grid.cellWidth
                    height: grid.cellHeight

                    AppTile {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        app: root.state.filteredApps[index]
                        theme: root.theme
                        tone: index
                        tileSize: Math.min(parent.width - 26, root.landscape ? 78 : 86)
                        onClicked: root.appLaunched(root.state.filteredApps[index])
                    }
                }
            }

            Column {
                visible: root.state.filteredApps.length === 0
                anchors.centerIn: parent
                spacing: 8
                Icon {
                    width: 32
                    height: 32
                    name: "search"
                    color: root.theme.textMuted
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "No apps match “" + root.state.appQuery + "”"
                    color: root.theme.textMuted
                    font.pixelSize: root.theme.scaledFont(15)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Component.onCompleted: {
        input.text = root.state.appQuery;
        if (root.state.surface === "launcher")
            input.forceActiveFocus();
    }
}
