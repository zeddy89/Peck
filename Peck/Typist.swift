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

    func type(_ rawText: String) {
        let text = TextNormalizer.normalizedLineBreaks(rawText)
        let source = CGEventSource(stateID: .combinedSessionState)
        let delayMicroseconds = UInt32(max(0, Preferences.shared.keystrokeDelayMs)) * 1_000
        let mapper = makeMapperIfNeeded()

        for character in text {
            autoreleasepool {
                typeCharacter(character, source: source, mapper: mapper)
            }
            if delayMicroseconds > 0 {
                usleep(delayMicroseconds)
            }
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

    // MARK: - Per-character dispatch

    private func typeCharacter(_ character: Character, source: CGEventSource?, mapper: KeyMapper?) {
        switch TextProcessing.classify(character) {
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
}
