import Carbon.HIToolbox

/// Pure formatting of a (keyCode, Carbon-modifier-mask) hotkey into a human string
/// like "⌃⌥⌘V", and helpers for validating a captured combo. Kept free of AppKit so
/// it can be unit-tested without synthesizing NSEvents.
enum HotkeyFormatter {

    /// Modifier glyphs in canonical macOS order: ⌃ ⌥ ⇧ ⌘.
    static func modifierSymbols(carbonModifiers: Int) -> String {
        var symbols = ""
        if carbonModifiers & controlKey != 0 { symbols += "⌃" }
        if carbonModifiers & optionKey  != 0 { symbols += "⌥" }
        if carbonModifiers & shiftKey   != 0 { symbols += "⇧" }
        if carbonModifiers & cmdKey     != 0 { symbols += "⌘" }
        return symbols
    }

    /// A label for the key itself (the US/ANSI physical legend, matching how most
    /// macOS apps render shortcuts), falling back to a numeric keycode.
    static func keyName(keyCode: Int) -> String {
        keyLabels[keyCode] ?? "Key \(keyCode)"
    }

    /// The full display string, e.g. "⌃⌥⌘V".
    static func displayString(keyCode: Int, carbonModifiers: Int) -> String {
        modifierSymbols(carbonModifiers: carbonModifiers) + keyName(keyCode: keyCode)
    }

    /// A hotkey is only usable if it pairs a key with at least one non-shift
    /// modifier (Command/Option/Control). A bare key — or a key plus only Shift —
    /// would collide with ordinary typing, so the recorder rejects it.
    static func isValid(keyCode: Int, carbonModifiers: Int) -> Bool {
        let requiredModifiers = controlKey | optionKey | cmdKey
        let allowedModifiers = requiredModifiers | shiftKey
        return carbonModifiers >= 0 && carbonModifiers & ~allowedModifiers == 0
            && (carbonModifiers & requiredModifiers) != 0 && keyLabels[keyCode] != nil
    }

    static let keyLabels: [Int: String] = {
        var labels: [Int: String] = [
            // Letters
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            // Digits
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            // Punctuation
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
            kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
            // Named / special keys
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_ANSI_KeypadEnter: "⌤",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            // Function keys
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return labels
    }()
}
