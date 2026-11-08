// Layout data for the in-shell fallback keyboard.
//
// These are deliberately small, purpose-specific layouts. The compositor
// keyboard (Squeekboard) owns layouts for other applications; this table only
// drives the shell's own fallback panel when no compositor keyboard appears.
// Nothing here stores or logs the text a key produces.

import QtQuick

QtObject {
    id: root

    readonly property var purposes: ["text", "terminal", "url", "password"]

    readonly property var views: ({
        text: {
            base: [
                "q w e r t y u i o p",
                "a s d f g h j k l",
                "show_upper z x c v b n m BackSpace",
                "show_numbers hide space . Return"
            ],
            upper: [
                "Q W E R T Y U I O P",
                "A S D F G H J K L",
                "show_upper Z X C V B N M BackSpace",
                "show_numbers hide space . Return"
            ],
            numbers: [
                "1 2 3 4 5 6 7 8 9 0",
                "@ # $ % & - _ + ( )",
                "show_symbols , quote ' : ; ! ? BackSpace",
                "show_letters hide space . Return"
            ],
            symbols: [
                "~ ` | · √ π τ ÷ × ¶",
                "© ® £ € ¥ ^ ° * { }",
                "show_numbers_from_symbols backslash / < > = [ ] BackSpace",
                "show_letters hide space . Return"
            ]
        },
        terminal: {
            base: [
                "Tab Ctrl Alt Shift ↑ ↓ ← →",
                "q w e r t y u i o p",
                ". a s d f g h j k l |",
                "show_upper z x c v b n m BackSpace",
                "show_numbers hide space / Return"
            ],
            upper: [
                "Tab Ctrl Alt Shift ↑ ↓ ← →",
                "Q W E R T Y U I O P",
                ". A S D F G H J K L |",
                "show_upper Z X C V B N M BackSpace",
                "show_numbers hide space / Return"
            ],
            numbers: [
                "Tab Ctrl Alt Shift ↑ ↓ ← →",
                "1 2 3 4 5 6 7 8 9 0",
                "backslash * # $ / & - + ( ) _",
                "show_symbols , quote ' : ; ! ? BackSpace",
                "show_letters hide space . Return"
            ],
            symbols: [
                "Tab Ctrl Alt Shift ↑ ↓ ← →",
                "~ ` | · √ π τ ÷ × ¶ @",
                "backslash © ® £ € ¥ ^ ° { } _",
                "show_numbers_from_symbols % | < > = [ ] BackSpace",
                "show_letters hide space . Return"
            ]
        },
        url: {
            base: [
                "q w e r t y u i o p",
                "a s d f g h j k l",
                "show_upper z x c v b n m BackSpace",
                "show_numbers hide space / . : Return"
            ],
            upper: [
                "Q W E R T Y U I O P",
                "A S D F G H J K L",
                "show_upper Z X C V B N M BackSpace",
                "show_numbers hide space / . : Return"
            ],
            numbers: [
                "1 2 3 4 5 6 7 8 9 0",
                "@ # $ % & - _ + ( )",
                "show_symbols , quote ' : ; ! ? BackSpace",
                "show_letters hide space / . : Return"
            ],
            symbols: [
                "~ ` | · √ π τ ÷ × ¶",
                "© ® £ € ¥ ^ ° * { }",
                "show_numbers_from_symbols backslash / < > = [ ] BackSpace",
                "show_letters hide space / . : Return"
            ]
        },
        password: {
            base: [
                "1 2 3 4 5 6 7 8 9 0",
                "q w e r t y u i o p",
                "a s d f g h j k l",
                "show_upper z x c v b n m BackSpace",
                "show_symbols hide space - _ Return"
            ],
            upper: [
                "1 2 3 4 5 6 7 8 9 0",
                "Q W E R T Y U I O P",
                "A S D F G H J K L",
                "show_upper Z X C V B N M BackSpace",
                "show_symbols hide space - _ Return"
            ],
            numbers: [
                "1 2 3 4 5 6 7 8 9 0",
                "@ # $ % & - _ + ( )",
                "show_symbols , quote ' : ; ! ? BackSpace",
                "show_letters hide space - _ Return"
            ],
            symbols: [
                "~ ` | · √ π τ ÷ × ¶",
                "© ® £ € ¥ ^ ° * { }",
                "show_numbers backslash / < > = [ ] BackSpace",
                "show_letters hide space - _ Return"
            ]
        }
    })

    readonly property var buttons: ({
        show_upper: { label: "⇧", action: "shift", outline: "mod" },
        BackSpace: { label: "⌫", action: "backspace", outline: "mod" },
        show_numbers: { label: "123", action: "view", view: "numbers", outline: "mod" },
        show_numbers_from_symbols: { label: "123", action: "view", view: "numbers", outline: "mod" },
        show_symbols: { label: "*/=", action: "view", view: "symbols", outline: "mod" },
        show_letters: { label: "ABC", action: "view", view: "base", outline: "mod" },
        space: { label: "space", action: "space", outline: "space" },
        Return: { label: "⏎", action: "return", outline: "mod" },
        hide: { label: "⌄", action: "hide", outline: "mod" },
        Tab: { label: "Tab", action: "tab", outline: "mod" },
        Ctrl: { label: "Ctrl", action: "modifier", modifier: "ctrl", outline: "mod" },
        Alt: { label: "Alt", action: "modifier", modifier: "alt", outline: "mod" },
        Shift: { label: "Shift", action: "modifier", modifier: "shift", outline: "mod" },
        "↑": { label: "↑", action: "move", delta: -1, outline: "mod" },
        "↓": { label: "↓", action: "move", delta: 1, outline: "mod" },
        "←": { label: "←", action: "move", delta: -1, outline: "mod" },
        "→": { label: "→", action: "move", delta: 1, outline: "mod" },
        quote: { label: "\"", text: "\"", outline: "default" },
        backslash: { label: "\\", text: "\\", outline: "default" }
    })

    function purposeKey(purpose) {
        const value = String(purpose || "text").toLowerCase();
        return root.purposes.indexOf(value) >= 0 ? value : "text";
    }

    function rowsFor(purpose, view) {
        const set = root.views[root.purposeKey(purpose)];
        if (!set)
            return [];
        return set[view] || set.base || [];
    }

    function viewFor(purpose, requested) {
        const set = root.views[root.purposeKey(purpose)];
        return set && set[requested] ? requested : "base";
    }

    function keyInfo(token) {
        if (root.buttons[token] !== undefined)
            return root.buttons[token];
        return { label: token, text: token, outline: "default" };
    }

    function isModifierActive(modifier, keyboardShift, keyboardModifier) {
        if (modifier === "shift")
            return keyboardShift;
        return keyboardModifier === modifier;
    }
}
