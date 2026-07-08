import Foundation

final class Preferences {

    static let shared = Preferences()

    enum TypingMode: Int {
        case keycodes = 0   // real virtual keycodes from the active layout (best for VM consoles)
        case unicode = 1    // direct character injection (broadest character support)
    }

    private enum Keys {
        static let preTypeDelayMs = "preTypeDelayMs"
        static let keystrokeDelayMs = "keystrokeDelayMs"
        static let typingMode = "typingMode"
        static let hotkeyEnabled = "hotkeyEnabled"
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
}
