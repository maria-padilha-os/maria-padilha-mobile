// Touch settings surface. Portrait shows an overview or a full-width page;
// landscape adds a persistent category rail. Every category is also reachable
// from the overview, so the surface remains usable without a mouse.

import QtQuick
import QtQuick.Layouts
import "../components"
import "../settings"
import "../settings/pages"

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape
    signal closed()

    readonly property var pages: [
        { id: "network", title: "Network", icon: "wifi", detail: "Wi-Fi, current connection and nearby networks" },
        { id: "display", title: "Display", icon: "brightness", detail: "Brightness, interface scale and preview" },
        { id: "sound", title: "Sound", icon: "volume", detail: "Output volume, mute and audio device" },
        { id: "battery", title: "Battery", icon: "battery", detail: "Charge state, power profile and warnings" },
        { id: "language", title: "Language", icon: "globe", detail: "Language, clock format and region" },
        { id: "about", title: "About", icon: "info", detail: "Device, image, shell and palette" }
    ]
    readonly property int margin: root.landscape ? 26 : 20
    readonly property string currentPage: root.state.settingsPage

    function pageTitle(page) {
        for (const entry of root.pages) {
            if (entry.id === page)
                return entry.title;
        }
        return "Settings";
    }

    function pageDetail(page) {
        for (const entry of root.pages) {
            if (entry.id === page)
                return entry.detail;
        }
        return "Network, display, sound, battery, language and about";
    }

    function openPage(page) {
        root.state.openSettingsPage(page);
    }

    function goBack() {
        if (root.currentPage === "index")
            root.closed();
        else
            root.openPage("index");
    }

    Keys.onEscapePressed: root.goBack()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: root.theme.surface

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.theme.outlineVariant
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.margin
                anchors.rightMargin: root.margin
                spacing: 12

                TouchButton {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    icon: "back"
                    iconSize: 22
                    vertical: true
                    background: root.theme.surfaceHigh
                    foreground: root.theme.text
                    radius: 16
                    onClicked: root.goBack()
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        width: parent.width
                        text: root.currentPage === "index" ? "Settings" : root.pageTitle(root.currentPage)
                        color: root.theme.text
                        font.pixelSize: root.landscape ? 26 : 24
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.pageDetail(root.currentPage)
                        color: root.theme.textMuted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    radius: 16
                    color: root.theme.primaryContainer
                    Icon {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        name: "settings"
                        color: root.theme.primaryContainerText
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                visible: root.landscape
                Layout.preferredWidth: root.landscape ? 248 : 0
                Layout.fillHeight: true
                color: root.theme.surfaceContainer

                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: 1
                    color: root.theme.outlineVariant
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    Repeater {
                        model: root.pages

                        delegate: Rectangle {
                            id: navItem
                            required property var modelData
                            readonly property bool active: root.currentPage === navItem.modelData.id

                            Layout.fillWidth: true
                            Layout.preferredHeight: 62
                            radius: 16
                            color: navItem.active ? root.theme.primaryContainer : root.theme.surfaceHigh
                            border.width: 1
                            border.color: navItem.active ? root.theme.primary : root.theme.outlineVariant

                            Accessible.role: Accessible.RadioButton
                            Accessible.name: navItem.modelData.title
                            Accessible.checked: navItem.active
                            Accessible.onPressAction: root.openPage(navItem.modelData.id)

                            TapHandler {
                                onTapped: root.openPage(navItem.modelData.id)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 10

                                Icon {
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    name: navItem.modelData.icon
                                    color: navItem.active
                                        ? root.theme.primaryContainerText : root.theme.containerMuted
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: navItem.modelData.title
                                    color: navItem.active
                                        ? root.theme.primaryContainerText : root.theme.containerText
                                    font.pixelSize: 15
                                    font.weight: navItem.active ? Font.DemiBold : Font.Medium
                                    elide: Text.ElideRight
                                }

                                Icon {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    name: "chevron_right"
                                    color: navItem.active
                                        ? root.theme.primaryContainerText : root.theme.containerMuted
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 58
                        radius: 14
                        color: root.theme.surfaceHigh
                        border.width: 1
                        border.color: root.theme.outlineVariant

                        Text {
                            anchors.fill: parent
                            anchors.margins: 10
                            text: "Touch targets stay at least 48 px. Settings use the existing Padilha config."
                            color: root.theme.containerMuted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Item {
                id: content
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridLayout {
                    id: overview
                    visible: root.currentPage === "index"
                    x: root.margin
                    y: root.margin
                    width: content.width - root.margin * 2
                    height: implicitHeight
                    columns: 2
                    rowSpacing: 12
                    columnSpacing: 12

                    Repeater {
                        model: root.pages

                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool active: root.currentPage === card.modelData.id

                            Layout.fillWidth: true
                            Layout.preferredHeight: 112
                            radius: 20
                            color: card.active ? root.theme.primaryContainer : root.theme.surfaceHigh
                            border.width: 1
                            border.color: card.active ? root.theme.primary : root.theme.outlineVariant

                            Accessible.role: Accessible.Button
                            Accessible.name: card.modelData.title
                            Accessible.description: card.modelData.detail
                            Accessible.onPressAction: root.openPage(card.modelData.id)

                            TapHandler {
                                onTapped: root.openPage(card.modelData.id)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 52
                                    Layout.preferredHeight: 52
                                    radius: 16
                                    color: card.active
                                        ? root.theme.primary : root.theme.surfaceContainer
                                    Icon {
                                        anchors.centerIn: parent
                                        width: 26
                                        height: 26
                                        name: card.modelData.icon
                                        color: card.active
                                            ? root.theme.primaryText : root.theme.highText
                                    }
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        width: parent.width
                                        text: card.modelData.title
                                        color: card.active
                                            ? root.theme.primaryContainerText : root.theme.highText
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: card.modelData.detail
                                        color: card.active
                                            ? root.theme.primaryContainerText : root.theme.highMuted
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }

                                Icon {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    name: "chevron_right"
                                    color: card.active
                                        ? root.theme.primaryContainerText : root.theme.highMuted
                                }
                            }
                        }
                    }
                }

                NetworkSettingsPage {
                    anchors.fill: parent
                    visible: root.currentPage === "network"
                    theme: root.theme
                    state: root.state
                    landscape: root.landscape
                }

                DisplaySettingsPage {
                    anchors.fill: parent
                    visible: root.currentPage === "display"
                    theme: root.theme
                    state: root.state
                    landscape: root.landscape
                }

                SoundSettingsPage {
                    anchors.fill: parent
                    visible: root.currentPage === "sound"
                    theme: root.theme
                    state: root.state
                    landscape: root.landscape
                }

                BatterySettingsPage {
                    anchors.fill: parent
                    visible: root.currentPage === "battery"
                    theme: root.theme
                    state: root.state
                    landscape: root.landscape
                }

                LanguageSettingsPage {
                    anchors.fill: parent
                    visible: root.currentPage === "language"
                    theme: root.theme
                    state: root.state
                    landscape: root.landscape
                }

                AboutSettingsPage {
                    anchors.fill: parent
                    visible: root.currentPage === "about"
                    theme: root.theme
                    state: root.state
                    landscape: root.landscape
                }
            }
        }
    }
}
