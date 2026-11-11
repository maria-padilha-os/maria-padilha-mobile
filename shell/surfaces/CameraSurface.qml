// Camera surface: a minimal libcamera/PipeWire consumer behind the
// xdg-desktop-portal Camera permission. The UI is explicit about every state:
// camera ready, permission denied, no portal, no camera and capture failure.
// When no camera is available it shows a generated test pattern, never a
// bundled photograph.

import QtQuick
import QtQuick.Layouts
import "../components"

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    signal closed()

    readonly property var camera: state.camera
    readonly property int margin: landscape ? 28 : 22
    readonly property int contentWidth: Math.min(flick.width - root.margin * 2,
                                                 root.landscape ? 620 : 10000)
    readonly property int previewHeight: root.landscape
        ? 300 : Math.max(220, Math.round(root.contentWidth * 0.72))

    onVisibleChanged: {
        if (visible)
            root.camera.activate();
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, content.implicitHeight + root.margin * 2)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: content
            x: Math.max(root.margin, (flick.width - width) / 2)
            y: root.margin
            width: root.contentWidth
            spacing: 14

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
                        text: "Camera"
                        color: root.theme.text
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.camera.statusLabel
                        color: root.theme.textMuted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                TouchButton {
                    icon: "camera"
                    vertical: false
                    iconSize: 22
                    background: root.theme.surfaceHigh
                    foreground: root.theme.text
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 16
                    enabled: !root.camera.busy
                    onClicked: root.camera.refresh()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statusLayout.implicitHeight + 28
                radius: 20
                color: root.theme.surfaceContainer
                border.width: 1
                border.color: root.camera.canCapture
                    ? root.theme.success : root.theme.outlineVariant

                ColumnLayout {
                    id: statusLayout
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            radius: 14
                            color: root.camera.canCapture
                                ? root.theme.successContainer : root.theme.surfaceHigh
                            Icon {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                name: "camera"
                                color: root.camera.canCapture
                                    ? root.theme.successContainerText : root.theme.text
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: root.camera.statusLabel
                                color: root.theme.containerText
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.camera.statusDetail
                                color: root.theme.containerMuted
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            implicitWidth: permissionLabel.implicitWidth + 18
                            implicitHeight: 30
                            radius: 15
                            color: root.camera.canCapture
                                ? root.theme.success : root.theme.surfaceHigh
                            Text {
                                id: permissionLabel
                                anchors.centerIn: parent
                                text: root.camera.permission === "granted"
                                    ? "Allowed"
                                    : (root.camera.portalAvailable ? "Portal" : "No portal")
                                color: root.camera.canCapture
                                    ? root.theme.successText : root.theme.highText
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: root.camera.canRequest || root.camera.busy

                        TouchButton {
                            visible: root.camera.canRequest
                            Layout.fillWidth: true
                            Layout.preferredHeight: 50
                            icon: "camera"
                            label: "Allow camera"
                            vertical: false
                            iconSize: 20
                            labelSize: 14
                            radius: 16
                            background: root.theme.primary
                            foreground: root.theme.primaryText
                            onClicked: root.camera.requestAccess()
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.camera.busy
                            text: "Requesting camera access…"
                            color: root.theme.textMuted
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            Rectangle {
                id: previewFrame
                Layout.fillWidth: true
                Layout.preferredHeight: root.previewHeight
                radius: 22
                clip: true
                color: root.theme.surfaceHigh
                border.width: 1
                border.color: root.theme.outlineVariant

                CameraTestPattern {
                    anchors.fill: parent
                    visible: root.camera.showsTestPattern
                }

                Image {
                    anchors.fill: parent
                    visible: root.camera.hasLiveFrame
                    source: root.camera.hasLiveFrame ? "file://" + root.camera.imagePath : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    cache: false
                    onStatusChanged: {
                        if (status === Image.Error && root.camera.hasLiveFrame)
                            root.camera.useTestPattern();
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 8
                    visible: root.camera.previewMode === "idle"

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 56
                        height: 56
                        name: "camera"
                        color: root.theme.textMuted
                    }

                    Text {
                        width: parent.width
                        text: "Preview is captured on demand"
                        color: root.theme.textMuted
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 12
                    implicitWidth: previewPill.implicitWidth + 20
                    implicitHeight: 32
                    radius: 16
                    color: root.camera.hasLiveFrame
                        ? root.theme.success : root.theme.inverseSurface
                    Text {
                        id: previewPill
                        anchors.centerIn: parent
                        text: root.camera.hasLiveFrame ? "Camera frame"
                            : (root.camera.showsTestPattern ? "Generated test pattern" : "No preview")
                        color: root.camera.hasLiveFrame
                            ? root.theme.successText : root.theme.inverseText
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: root.camera.showsTestPattern
                    height: patternNote.implicitHeight + 16
                    color: root.theme.scrim
                    opacity: 0.78
                    Text {
                        id: patternNote
                        anchors.fill: parent
                        anchors.margins: 8
                        text: "Generated test pattern · not a photograph or camera image"
                        color: "#ffffff"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                TouchButton {
                    visible: root.camera.canCapture
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    icon: "camera"
                    label: root.camera.busy ? "Capturing…" : "Capture"
                    vertical: false
                    iconSize: 22
                    labelSize: 15
                    radius: 18
                    enabled: !root.camera.busy
                    background: root.theme.primary
                    foreground: root.theme.primaryText
                    onClicked: root.camera.capture()
                }

                TouchButton {
                    visible: !root.camera.canCapture
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    icon: "image"
                    label: "Show test pattern"
                    vertical: false
                    iconSize: 22
                    labelSize: 15
                    radius: 18
                    background: root.theme.surfaceHigh
                    foreground: root.theme.text
                    onClicked: root.camera.useTestPattern()
                }

                TouchButton {
                    visible: root.camera.canCapture
                    Layout.preferredHeight: 56
                    Layout.minimumWidth: 56
                    icon: "image"
                    vertical: false
                    iconSize: 22
                    radius: 18
                    background: root.theme.surfaceHigh
                    foreground: root.theme.text
                    onClicked: root.camera.useTestPattern()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.camera.lastError.length > 0
                text: "Camera status: " + root.camera.lastError
                color: root.theme.danger
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                text: "Captures stay in this session. The repository bundles no photographs or test images; the fallback pattern is generated locally."
                color: root.theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            Item { Layout.fillHeight: true }
        }
    }
}
