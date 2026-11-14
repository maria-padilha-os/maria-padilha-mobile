// Touch-friendly select row. Options expand inline instead of opening a
// separate popup, so the control works without a mouse and stays inside the
// page's Flickable.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    property string icon: ""
    property string label: ""
    property string description: ""
    property var options: []
    property var currentValue: undefined
    property bool enabled: true
    signal selected(var value)

    Layout.fillWidth: true
    implicitHeight: card.height + (expanded ? optionsColumn.implicitHeight + 8 : 0)
    opacity: root.enabled ? 1 : 0.55
    property bool expanded: false

    Accessible.role: Accessible.ComboBox
    Accessible.name: root.label
    Accessible.description: root.description
    Accessible.onPressAction: if (root.enabled) root.expanded = !root.expanded

    function _optionLabel(option) {
        if (!option)
            return "";
        return option.label !== undefined ? option.label : String(option.value);
    }

    function _optionValue(option) {
        return option ? option.value : undefined;
    }

    function _currentLabel() {
        for (const option of root.options) {
            if (_optionValue(option) === root.currentValue)
                return _optionLabel(option);
        }
        return root.options.length > 0 ? _optionLabel(root.options[0]) : "—";
    }

    function _select(option) {
        root.expanded = false;
        root.selected(_optionValue(option));
    }

    SettingsRowCard {
        id: card
        theme: root.theme
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 68

        TapHandler {
            enabled: root.enabled
            onTapped: root.expanded = !root.expanded
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            spacing: 12

            Icon {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                name: root.icon
                visible: root.icon.length > 0
                color: root.theme.highMuted
            }

            Column {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    width: parent.width
                    text: root.label
                    color: root.theme.highText
                    font.pixelSize: root.theme.scaledFont(16)
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: root.description.length > 0
                    text: root.description
                    color: root.theme.highMuted
                    font.pixelSize: root.theme.scaledFont(12)
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.maximumWidth: parent.width * 0.42
                text: root._currentLabel()
                color: root.theme.accent
                font.pixelSize: root.theme.scaledFont(14)
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Icon {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                name: root.expanded ? "arrow_up" : "chevron_right"
                color: root.theme.highMuted
                rotation: root.expanded ? 90 : 0
            }
        }
    }

    ColumnLayout {
        id: optionsColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: card.bottom
        anchors.topMargin: root.expanded ? 8 : 0
        visible: root.expanded
        spacing: 6

        Repeater {
            model: root.options

            delegate: Rectangle {
                id: option
                required property var modelData
                readonly property bool active: root._optionValue(option.modelData) === root.currentValue

                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: 14
                color: option.active ? root.theme.primaryContainer : root.theme.surfaceContainer
                border.width: 1
                border.color: option.active ? root.theme.primary : root.theme.outlineVariant

                Accessible.role: Accessible.RadioButton
                Accessible.name: root._optionLabel(option.modelData)
                Accessible.checked: option.active
                Accessible.onPressAction: root._select(option.modelData)

                TapHandler {
                    onTapped: root._select(option.modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 14
                    spacing: 10

                    Column {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            width: parent.width
                            text: root._optionLabel(option.modelData)
                            color: option.active ? root.theme.primaryContainerText : root.theme.containerText
                            font.pixelSize: root.theme.scaledFont(15)
                            font.weight: option.active ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: option.modelData.detail !== undefined &&
                                    String(option.modelData.detail).length > 0
                            text: option.modelData.detail !== undefined ? option.modelData.detail : ""
                            color: option.active ? root.theme.primaryContainerText : root.theme.containerMuted
                            font.pixelSize: root.theme.scaledFont(11)
                            elide: Text.ElideRight
                        }
                    }

                    Icon {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        visible: option.active
                        name: "check"
                        color: root.theme.primaryContainerText
                    }
                }
            }
        }
    }
}
