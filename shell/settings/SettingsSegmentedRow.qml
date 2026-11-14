// A row of mutually exclusive large choice buttons. Used for display scale and
// power profile where a select list would add an unnecessary second tap.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    property string label: ""
    property string description: ""
    property var options: []
    property var currentValue: undefined
    property bool enabled: true
    signal selected(var value)

    Layout.fillWidth: true
    implicitHeight: Math.max(84, column.implicitHeight)

    function _optionLabel(option) {
        return option && option.label !== undefined ? option.label : String(option ? option.value : "");
    }

    function _optionValue(option) {
        return option ? option.value : undefined;
    }

    Column {
        id: column
        anchors.fill: parent
        spacing: 6

        Text {
            width: parent.width
            text: root.label
            color: root.theme.text
            font.pixelSize: 15
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.description.length > 0
            text: root.description
            color: root.theme.textMuted
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        RowLayout {
            width: parent.width
            height: 52
            spacing: 6
            opacity: root.enabled ? 1 : 0.55

            Repeater {
                model: root.options

                delegate: TouchButton {
                    id: choice
                    required property var modelData
                    readonly property bool isCurrent: root._optionValue(choice.modelData) === root.currentValue

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    enabled: root.enabled
                    label: root._optionLabel(choice.modelData)
                    labelSize: 13
                    vertical: true
                    iconSize: 0
                    active: choice.isCurrent
                    background: root.theme.surfaceHigh
                    foreground: root.theme.text
                    borderColor: choice.isCurrent ? root.theme.accent : root.theme.outlineVariant
                    activeBackground: root.theme.primaryContainer
                    activeForeground: root.theme.primaryContainerText
                    radius: 14
                    onClicked: root.selected(root._optionValue(choice.modelData))
                }
            }
        }
    }
}
