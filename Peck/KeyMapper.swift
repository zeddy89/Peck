import AppKit
import Carbon

/// Builds a character → (virtual keycode, modifier flags) table from the
/// user's *current* keyboard layout using UCKeyTranslate. This means the
/// keycode typing engine works correctly on QWERTY, AZERTY, Dvorak, or
/// anything else, instead of assuming a hardcoded US map.
final class KeyMapper {

    struct Stroke {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    private var map: [Character: Stroke] = [:]

    init?() {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data

        // Modifier combos in priority order. First mapping for a character
        // wins, so unmodified keys beat shifted ones, which beat option ones.
        let shiftBits = UInt32((shiftKey >> 8) & 0xFF)
        let optionBits = UInt32((optionKey >> 8) & 0xFF)
        let combos: [(carbonModifiers: UInt32, flags: CGEventFlags)] = [
            (0, []),
            (shiftBits, .maskShift),
            (optionBits, .maskAlternate),
            (shiftBits | optionBits, [.maskShift, .maskAlternate]),
        ]

        let keyboardType = UInt32(LMGetKbdType())

        layoutData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }

            for combo in combos {
                for keyCode: UInt16 in 0..<128 {
                    var deadKeyState: UInt32 = 0
                    var actualLength = 0
                    var characters = [UniChar](repeating: 0, count: 4)

                    let status = UCKeyTranslate(
                        layout,
                        keyCode,
                        UInt16(kUCKeyActionDown),
                        combo.carbonModifiers,
                        keyboardType,
                        OptionBits(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        characters.count,
                        &actualLength,
                        &characters)

                    guard status == noErr, actualLength == 1 else { continue }

                    let produced = String(utf16CodeUnits: characters, count: actualLength)
                    guard let character = produced.first,
                          let scalar = character.unicodeScalars.first,
                          scalar.value >= 0x20,
                          scalar.value != 0x7F,
                          map[character] == nil
                    else { continue }

                    map[character] = Stroke(keyCode: CGKeyCode(keyCode), flags: combo.flags)
                }
            }
        }

        if map.isEmpty { return nil }
    }

    func stroke(for character: Character) -> Stroke? {
        map[character]
    }
}
