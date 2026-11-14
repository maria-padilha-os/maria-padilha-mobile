// Shared rounded card used by every mobile settings row. The desktop Nexus
// rows use the same grouped-card language; this version has no Caelestia
// Tokens dependency so it also runs in the minimal QEMU guest.

import QtQuick
import "../components"

Rectangle {
    id: root

    required property Theme theme
    property bool interactive: false
    property color background: root.theme.surfaceHigh
    property color borderColor: root.theme.outlineVariant

    implicitHeight: 64
    radius: 18
    color: root.background
    border.width: 1
    border.color: root.borderColor
}
