// Section label for a settings page. Mirrors the desktop Nexus SectionHeader
// while using the mobile shell's Theme roles instead of Caelestia tokens.

import QtQuick
import QtQuick.Layouts
import "../components"

Text {
    id: root

    required property Theme theme
    property bool first: false

    Layout.fillWidth: true
    Layout.topMargin: root.first ? 0 : 18
    Layout.bottomMargin: 4
    Layout.leftMargin: 4
    text: ""
    color: root.theme.textMuted
    font.pixelSize: 12
    font.weight: Font.DemiBold
    font.letterSpacing: 0.6
    font.capitalization: Font.AllUppercase
    elide: Text.ElideRight
}
