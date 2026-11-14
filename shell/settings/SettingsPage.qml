// Scrollable page body shared by every mobile settings page. The surface owns
// the title/back row; this component owns the padded, scrollable content.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    required property bool landscape
    property int bottomPadding: 24
    default property alias content: column.data

    readonly property int margin: root.landscape ? 26 : 20

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, column.implicitHeight + root.margin + root.bottomPadding)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: column
            x: root.margin
            y: root.margin
            width: flick.width - root.margin * 2
            spacing: 8
        }
    }
}
