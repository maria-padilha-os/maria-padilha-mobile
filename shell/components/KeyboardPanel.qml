// In-shell fallback keyboard.
//
// Squeekboard is the compositor keyboard and the primary backend. This panel
// exists for environments where no compositor keyboard is available (desktop
// development, offscreen tests, or a compositor without text-input support)
// and for the manual QEMU fallback check. It commits text directly to the
// focused TextInput; it does not write, persist or log that text.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Theme theme
    required property ShellState state
    required property bool landscape

    readonly property int keySpacing: landscape ? 5 : 6
    readonly property int edgeMargin: landscape ? 6 : 8
    readonly property var rows: layouts.rowsFor(root.state.keyboardPurpose, root.state.keyboardView)
    readonly property int rowCount: Math.max(1, root.rows.length)
    readonly property real rowHeight: {
        const available = root.landscape ? 260 : 400;
        return Math.max(46, Math.min(root.landscape ? 58 : 82, available / root.rowCount));
    }
    readonly property real panelHeight: root.state.inlineKeyboardActive
        ? Math.round(root.rowHeight * root.rowCount + root.keySpacing * (root.rowCount - 1) + root.edgeMargin * 2)
        : 0
    readonly property real contentWidth: Math.min(width - root.edgeMargin * 2, root.landscape ? 980 : width)

    visible: root.state.inlineKeyboardActive
    height: root.panelHeight
    clip: true
    z: 20

    KeyboardLayouts { id: layouts }

    Rectangle {
        anchors.fill: parent
        color: root.theme.surfaceHigh
        border.width: 1
        border.color: root.theme.outlineVariant
    }

    ColumnLayout {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.edgeMargin
        anchors.bottomMargin: root.edgeMargin
        width: root.contentWidth
        spacing: root.keySpacing

        Repeater {
            model: root.rows

            delegate: RowLayout {
                id: rowDelegate
                required property string modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.keySpacing

                Repeater {
                    model: rowDelegate.modelData.split(/\s+/)

                    delegate: KeyboardKey {
                        id: key
                        required property string modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: root.keyWeight(modelData)
                        Layout.minimumWidth: 44

                        theme: root.theme
                        token: modelData
                        info: layouts.keyInfo(modelData)
                        active: {
                            if (info.action === "shift")
                                return root.state.keyboardShift;
                            if (info.action === "modifier")
                                return root.state.keyboardModifier === info.modifier;
                            return false;
                        }
                        onActivated: root.activate(modelData)
                    }
                }
            }
        }
    }

    function keyWeight(token) {
        if (token === "space")
            return 4.0;
        if (["show_upper", "BackSpace", "Return", "hide", "show_numbers",
             "show_numbers_from_symbols", "show_letters", "show_symbols",
             "Tab", "Ctrl", "Alt", "Shift"].indexOf(token) >= 0)
            return 1.35;
        if (token.length > 1)
            return 1.15;
        return 1.0;
    }

    function activate(token) {
        const info = layouts.keyInfo(token);
        switch (info.action) {
        case "shift":
            root.state.keyboardShift = !root.state.keyboardShift;
            return;
        case "backspace":
            root.state.keyboardBackspace();
            return;
        case "view":
            root.state.keyboardSetView(info.view);
            return;
        case "space":
            root.state.keyboardInsert(" ");
            return;
        case "return":
            root.state.keyboardReturn();
            return;
        case "tab":
            root.state.keyboardInsert("\t");
            return;
        case "hide":
            root.state.hideKeyboard();
            return;
        case "move":
            root.state.keyboardMove(info.delta);
            return;
        case "modifier":
            if (info.modifier === "shift") {
                root.state.keyboardShift = !root.state.keyboardShift;
            } else {
                root.state.keyboardModifier =
                    root.state.keyboardModifier === info.modifier ? "" : info.modifier;
            }
            return;
        }

        let text = info.text !== undefined ? info.text : token;
        if (root.state.keyboardShift && text.length === 1)
            text = text.toUpperCase();
        root.state.keyboardInsert(text);
        if (root.state.keyboardShift)
            root.state.keyboardShift = false;
    }
}
