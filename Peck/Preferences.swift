import Foundation
import Carbon.HIToolbox

final class Preferences {

    static let shared = Preferences()

    enum TypingMode: Int {
        case keycodes = 0   // real virtual keycodes from the active layout (best for VM consoles)
        case unicode = 1    // direct character injection (broadest character support)
    }

    enum SpeedChoice: Int, CaseIterable {
        case fast = 2, medium = 5, slow = 15
        var title: String {
            switch self {
            case .fast: return "Fast"
            case .medium: return "Medium"
            case .slow: return "Slow"
            }
        }
    }
    var speedChoice: SpeedChoice? { SpeedChoice(rawValue: keystrokeDelayMs) }
    /// Character delay only. Advanced hold and Return pacing remain explicit.
    func applySpeed(_ speed: SpeedChoice) { keystrokeDelayMs = speed.rawValue }
    var confirmBeforeTyping: Bool {
        get { defaults.bool(forKey: "confirmBeforeTyping") }
        set { defaults.set(newValue, forKey: "confirmBeforeTyping") }
    }

    enum Preset: Int, CaseIterable {
        case custom, native, console, vim, conservative, vimBracketed
        var title: String {
            switch self {
            case .custom: return "Custom (keep current settings)"
            case .native: return "Native editor"
            case .console: return "Console (fast, unverified)"
            case .vim: return "Vim / vi (paste + Insert mode required)"
            case .conservative: return "Console (conservative, optional)"
            case .vimBracketed: return "Vim bracketed paste (experimental)"
            }
        }
    }

    /// Presets are explicit actions. Registering new defaults never migrates an
    /// existing user's delays or editor workaround behind their back.
    func apply(_ preset: Preset) {
        guard preset != .custom else { return }
        typingMode = preset == .native ? .unicode : .keycodes
        preTypeDelayMs = preset == .native ? 400 : (preset == .conservative ? 1000 : 600)
        keystrokeDelayMs = preset == .conservative ? 40 : 2
        keyHoldMs = preset == .conservative ? 10 : 0
        newlineDelayMs = preset == .conservative ? 150 : 0
        strictKeycodes = preset != .native
        warnOnReturn = true
        pressReturnAfterTyping = false
        stripTrailingNewline = true
        indentWorkaround = preset == .vimBracketed ? .bracketedPaste : .none
    }

    var keyHoldMs: Int {
        get { min(100, max(0, defaults.integer(forKey: "keyHoldMs"))) }
        set { defaults.set(min(100, max(0, newValue)), forKey: "keyHoldMs") }
    }
    var newlineDelayMs: Int {
        get { min(10000, max(0, defaults.integer(forKey: "newlineDelayMs"))) }
        set { defaults.set(min(10000, max(0, newValue)), forKey: "newlineDelayMs") }
    }
    var strictKeycodes: Bool {
        get { defaults.bool(forKey: "strictKeycodes") }
        set { defaults.set(newValue, forKey: "strictKeycodes") }
    }
    var warnOnReturn: Bool {
        get { defaults.bool(forKey: "warnOnReturn") }
        set { defaults.set(newValue, forKey: "warnOnReturn") }
    }
    var hasSeenTypingTest: Bool {
        get { defaults.bool(forKey: "hasSeenTypingTest") }
        set { defaults.set(newValue, forKey: "hasSeenTypingTest") }
    }

    /// Default global hotkey: ⌃⌥⌘V.
    enum HotkeyDefault {
        static let keyCode = Int(kVK_ANSI_V)
        static let carbonModifiers = Int(controlKey | optionKey | cmdKey)
    }

    var currentFocusHotkeyEnabled: Bool {
        get { defaults.bool(forKey: "currentFocusHotkeyEnabled") }
        set { defaults.set(newValue, forKey: "currentFocusHotkeyEnabled") }
    }
    var currentFocusHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "currentFocusHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "currentFocusHotkeyKeyCode") }
    }
    var currentFocusHotkeyModifiers: Int {
        get { defaults.integer(forKey: "currentFocusHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "currentFocusHotkeyModifiers") }
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
            "confirmBeforeTyping": false,
            "currentFocusHotkeyEnabled": true,
            "currentFocusHotkeyKeyCode": Int(kVK_ANSI_V),
            "currentFocusHotkeyModifiers": Int(controlKey | optionKey),
            "keyHoldMs": 0,
            "newlineDelayMs": 0,
            "strictKeycodes": false,
            "warnOnReturn": true,
            Keys.preTypeDelayMs: 400,
            Keys.keystrokeDelayMs: 2,
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
        get { min(10000, max(0, defaults.integer(forKey: Keys.preTypeDelayMs))) }
        set { defaults.set(min(10000, max(0, newValue)), forKey: Keys.preTypeDelayMs) }
    }

    /// Delay between individual keystrokes. Laggy consoles like it slower.
    var keystrokeDelayMs: Int {
        get { min(10000, max(0, defaults.integer(forKey: Keys.keystrokeDelayMs))) }
        set { defaults.set(min(10000, max(0, newValue)), forKey: Keys.keystrokeDelayMs) }
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
        get { min(10000000, max(0, defaults.integer(forKey: Keys.largePasteThreshold))) }
        set { defaults.set(min(10000000, max(0, newValue)), forKey: Keys.largePasteThreshold) }
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
