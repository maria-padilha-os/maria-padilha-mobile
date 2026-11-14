// Home surface. Portrait stacks the clock above the actions; landscape puts
// them side by side and uses more grid columns.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape
    signal appsRequested()
    signal notificationsRequested()

    readonly property int margin: landscape ? 28 : 22
    readonly property int pinnedColumns: landscape ? 6 : 4

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, layout.implicitHeight + root.margin * 2)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: layout
            x: root.margin
            y: root.margin
            width: flick.width - root.margin * 2
            spacing: root.landscape ? 18 : 22

            Loader {
                Layout.fillWidth: true
                sourceComponent: root.landscape ? heroLandscape : heroPortrait
            }

            NotificationSummary {
                Layout.fillWidth: true
                theme: root.theme
                state: root.state
                landscape: root.landscape
                onClicked: root.notificationsRequested()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Pinned"
                        color: root.theme.text
                        font.pixelSize: root.theme.scaledFont(17)
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    TouchButton {
                        theme: root.theme
                        icon: "apps"
                        label: "All apps"
                        vertical: false
                        iconSize: 18
                        labelSize: 13
                        implicitHeight: 48
                        foreground: root.theme.accent
                        onClicked: root.appsRequested()
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: root.pinnedColumns
                    rowSpacing: 16
                    columnSpacing: 8

                    Repeater {
                        model: Math.min(8, root.state.apps.length)
                        delegate: AppTile {
                            required property int index
                            app: root.state.apps[index]
                            theme: root.theme
                            tone: index
                            tileSize: root.landscape ? 64 : 68
                            Layout.fillWidth: true
                            Layout.preferredHeight: (root.landscape ? 64 : 68)
                                + root.theme.scaledFont(12) + 18
                            onClicked: root.state.launch(root.state.apps[index])
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: heroPortrait
        ColumnLayout {
            spacing: 14
            ClockBlock {
                Layout.fillWidth: true
                theme: root.theme
                timeSize: 92
            }
            QuickActions {
                Layout.fillWidth: true
                theme: root.theme
                state: root.state
            }
        }
    }

    Component {
        id: heroLandscape
        RowLayout {
            spacing: 28
            ClockBlock {
                Layout.fillWidth: true
                Layout.preferredWidth: 400
                theme: root.theme
                timeSize: 78
                centered: false
            }
            QuickActions {
                Layout.preferredWidth: 430
                Layout.maximumWidth: 480
                theme: root.theme
                state: root.state
                landscape: true
            }
        }
    }
}
