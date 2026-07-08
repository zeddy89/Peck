import AppKit
import Carbon.HIToolbox

/// Turns clipboard text into synthetic keystrokes.
///
/// Two engines:
///  - **Keycodes** (default): resolves each character to a real virtual
///    keycode + modifiers from the active keyboard layout and presses the
///    actual keys, including physical Shift/Option press-and-release. This is
///    what noVNC, vSphere web consoles, and RDP want, because they key off
///    hardware keycodes rather than injected text.
///  - **Unicode**: injects characters directly via
///    `keyboardSetUnicodeString`. Handles any character in any script, but
///    some VNC-style consoles ignore or mangle it.
///
/// Characters the keycode engine can't map (emoji, characters outside the
/// current layout) automatically fall back to unicode injection.
final class Typist {

    static let shared = Typist()
    private init() {}

    /// Fired on the main thread when typing starts (`true`) and when it ends
    /// (`false`) — whether it finished or was aborted. Drives the menu-bar
    /// "typing" icon and the Esc/hotkey abort monitor.
    var onTypingStateChange: ((Bool) -> Void)?

    /// Typing runs on its own serial queue so it never blocks the main thread and
    /// so a single in-flight job can be cancelled cleanly.
    private let queue = DispatchQueue(label: "dev.homelab.peck.typist", qos: .userInitiated)
    private let lock = NSLock()
    private var _cancelled = false
    private var _isTyping = false

    /// Whether a typing job is currently running. Used to route the global hotkey
    /// to "abort" instead of "arm" while typing.
    var isTyping: Bool { lock.withLock { _isTyping } }

    /// Enqueue clipboard text to be typed. Returns immediately; typing proceeds on
    /// the dedicated queue and can be stopped with `cancel()`.
    func type(_ rawText: String) {
        lock.withLock { _cancelled = false }
        queue.async { [weak self] in
            self?.run(rawText)
        }
    }

    /// Request that in-progress typing stop as soon as possible. Thread-safe.
    func cancel() {
        lock.withLock { _cancelled = true }
    }

    private var isCancelled: Bool { lock.withLock { _cancelled } }

    private func run(_ rawText: String) {
        let prefs = Preferences.shared
        let keys = TextProcessing.keySequence(
            for: rawText,
            stripTrailingNewline: prefs.stripTrailingNewline,
            appendReturn: prefs.pressReturnAfterTyping)

        guard !keys.isEmpty else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        let delayMicroseconds = UInt32(max(0, prefs.keystrokeDelayMs)) * 1_000
        let mapper = makeMapperIfNeeded()

        setTyping(true)
        defer { setTyping(false) }

        for key in keys {
            if isCancelled {
                // A character was typed atomically (press() balances its own
                // modifiers), so nothing should be held — but release defensively
                // so an aborted shifted/optioned keystroke can never strand a
                // modifier physically down.
                releaseModifiers(source: source)
                break
            }
            autoreleasepool {
                emit(key, source: source, mapper: mapper)
            }
            if delayMicroseconds > 0 {
                usleep(delayMicroseconds)
            }
        }
    }

    private func setTyping(_ typing: Bool) {
        lock.withLock { _isTyping = typing }
        DispatchQueue.main.async { [weak self] in
            self?.onTypingStateChange?(typing)
        }
    }

    private func makeMapperIfNeeded() -> KeyMapper? {
        guard Preferences.shared.typingMode == .keycodes else { return nil }

        if Thread.isMainThread {
            return KeyMapper()
        }

        return DispatchQueue.main.sync {
            KeyMapper()
        }
    }

    // MARK: - Per-key dispatch

    private func emit(_ key: TypedKey, source: CGEventSource?, mapper: KeyMapper?) {
        switch key {
        case .returnKey:
            press(keyCode: CGKeyCode(kVK_Return), flags: [], source: source)
        case .tab:
            press(keyCode: CGKeyCode(kVK_Tab), flags: [], source: source)
        case .literal(let literal):
            if let mapper, let stroke = mapper.stroke(for: literal) {
                press(keyCode: stroke.keyCode, flags: stroke.flags, source: source)
            } else {
                injectUnicode(literal, source: source)
            }
        }
    }

    // MARK: - Keycode engine

    private func press(keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource?) {
        // Physically press modifiers first. VNC-style consoles track modifier
        // state from real key events, not just event flags.
        if flags.contains(.maskShift) {
            postKey(CGKeyCode(kVK_Shift), down: true, flags: flags, source: source)
        }
        if flags.contains(.maskAlternate) {
            postKey(CGKeyCode(kVK_Option), down: true, flags: flags, source: source)
        }

        postKey(keyCode, down: true, flags: flags, source: source)
        postKey(keyCode, down: false, flags: flags, source: source)

        if flags.contains(.maskAlternate) {
            postKey(CGKeyCode(kVK_Option), down: false, flags: [], source: source)
        }
        if flags.contains(.maskShift) {
            postKey(CGKeyCode(kVK_Shift), down: false, flags: [], source: source)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Unicode engine

    private func injectUnicode(_ character: Character, source: CGEventSource?) {
        let units = Array(String(character).utf16)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Abort safety

    /// Post key-up for every modifier we might synthesize, so aborting mid-stroke
    /// can never leave Shift/Option/Command/Control stuck down. A key-up for a key
    /// that isn't down is a harmless no-op.
    private func releaseModifiers(source: CGEventSource?) {
        let modifiers = [
            kVK_Shift, kVK_RightShift,
            kVK_Option, kVK_RightOption,
            kVK_Command, kVK_RightCommand,
            kVK_Control, kVK_RightControl,
        ]
        for modifier in modifiers {
            postKey(CGKeyCode(modifier), down: false, flags: [], source: source)
        }
    }
}
