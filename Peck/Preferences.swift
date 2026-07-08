import Foundation
import Carbon.HIToolbox

final class Preferences {

    static let shared = Preferences()

    enum TypingMode: Int {
        case keycodes = 0   // real virtual keycodes from the active layout (best for VM consoles)
        case unicode = 1    // direct character injection (broadest character support)
    }

    /// Default global hotkey: ⌃⌥⌘V.
    enum HotkeyDefault {
        static let keyCode = Int(kVK_ANSI_V)
        static let carbonModifiers = Int(controlKey | optionKey | cmdKey)
    }

    private enum Keys {
        static let preTypeDelayMs = "preTypeDelayMs"
        static let keystrokeDelayMs = "keystrokeDelayMs"
        static let typingMode = "typingMode"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyCarbonModifiers = "hotkeyCarbonModifiers"
        static let largePasteThreshold = "largePasteThreshold"
        static let pressReturnAfterTyping = "pressReturnAfterTyping"
        static let stripTrailingNewline = "stripTrailingNewline"
        static let indentWorkaround = "indentWorkaround"
    }

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can run against a throwaway suite instead
    /// of polluting `UserDefaults.standard`. Production always uses `.shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.preTypeDelayMs: 400,
            Keys.keystrokeDelayMs: 15,
            Keys.typingMode: TypingMode.keycodes.rawValue,
            Keys.hotkeyEnabled: true,
            Keys.hotkeyKeyCode: HotkeyDefault.keyCode,
            Keys.hotkeyCarbonModifiers: HotkeyDefault.carbonModifiers,
            Keys.largePasteThreshold: 1000,
            Keys.pressReturnAfterTyping: false,
            Keys.stripTrailingNewline: true,
            Keys.indentWorkaround: IndentWorkaround.none.rawValue,
        ])
    }

    /// Delay between the synthetic focus click and the first keystroke.
    var preTypeDelayMs: Int {
        get { defaults.integer(forKey: Keys.preTypeDelayMs) }
        set { defaults.set(newValue, forKey: Keys.preTypeDelayMs) }
    }

    /// Delay between individual keystrokes. Laggy consoles like it slower.
    var keystrokeDelayMs: Int {
        get { defaults.integer(forKey: Keys.keystrokeDelayMs) }
        set { defaults.set(newValue, forKey: Keys.keystrokeDelayMs) }
    }

    var typingMode: TypingMode {
        get { TypingMode(rawValue: defaults.integer(forKey: Keys.typingMode)) ?? .keycodes }
        set { defaults.set(newValue.rawValue, forKey: Keys.typingMode) }
    }

    var hotkeyEnabled: Bool {
        get { defaults.bool(forKey: Keys.hotkeyEnabled) }
        set { defaults.set(newValue, forKey: Keys.hotkeyEnabled) }
    }

    /// Virtual keycode of the global hotkey's main key.
    var hotkeyKeyCode: Int {
        get { defaults.integer(forKey: Keys.hotkeyKeyCode) }
        set { defaults.set(newValue, forKey: Keys.hotkeyKeyCode) }
    }

    /// Carbon modifier mask (controlKey/optionKey/shiftKey/cmdKey) of the global hotkey.
    var hotkeyCarbonModifiers: Int {
        get { defaults.integer(forKey: Keys.hotkeyCarbonModifiers) }
        set { defaults.set(newValue, forKey: Keys.hotkeyCarbonModifiers) }
    }

    /// Above this many characters, arming asks for confirmation before typing.
    /// 0 disables the guardrail entirely.
    var largePasteThreshold: Int {
        get { defaults.integer(forKey: Keys.largePasteThreshold) }
        set { defaults.set(newValue, forKey: Keys.largePasteThreshold) }
    }

    /// Press Return once after the clipboard has been typed.
    var pressReturnAfterTyping: Bool {
        get { defaults.bool(forKey: Keys.pressReturnAfterTyping) }
        set { defaults.set(newValue, forKey: Keys.pressReturnAfterTyping) }
    }

    /// Drop a single trailing newline before typing. Terminal copies almost always
    /// drag one along, and in a console that newline runs the last command.
    var stripTrailingNewline: Bool {
        get { defaults.bool(forKey: Keys.stripTrailingNewline) }
        set { defaults.set(newValue, forKey: Keys.stripTrailingNewline) }
    }

    /// Opt-in workaround for targets that auto-indent what Peck types.
    var indentWorkaround: IndentWorkaround {
        get { IndentWorkaround(rawValue: defaults.integer(forKey: Keys.indentWorkaround)) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Keys.indentWorkaround) }
    }
}
