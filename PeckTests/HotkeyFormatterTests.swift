import XCTest
import Carbon.HIToolbox

final class HotkeyFormatterTests: XCTestCase {

    func testDefaultHotkeyDisplaysAsControlOptionCommandV() {
        let mods = controlKey | optionKey | cmdKey
        XCTAssertEqual(HotkeyFormatter.displayString(keyCode: kVK_ANSI_V, carbonModifiers: mods), "⌃⌥⌘V")
    }

    func testModifierOrderIsCanonical() {
        let all = controlKey | optionKey | shiftKey | cmdKey
        XCTAssertEqual(HotkeyFormatter.modifierSymbols(carbonModifiers: all), "⌃⌥⇧⌘")
    }

    func testIndividualModifiers() {
        XCTAssertEqual(HotkeyFormatter.modifierSymbols(carbonModifiers: cmdKey), "⌘")
        XCTAssertEqual(HotkeyFormatter.modifierSymbols(carbonModifiers: shiftKey), "⇧")
        XCTAssertEqual(HotkeyFormatter.modifierSymbols(carbonModifiers: 0), "")
    }

    func testKeyNames() {
        XCTAssertEqual(HotkeyFormatter.keyName(keyCode: kVK_ANSI_A), "A")
        XCTAssertEqual(HotkeyFormatter.keyName(keyCode: kVK_ANSI_0), "0")
        XCTAssertEqual(HotkeyFormatter.keyName(keyCode: kVK_Space), "Space")
        XCTAssertEqual(HotkeyFormatter.keyName(keyCode: kVK_Return), "↩")
        XCTAssertEqual(HotkeyFormatter.keyName(keyCode: kVK_F5), "F5")
    }

    func testUnknownKeycodeFallsBack() {
        XCTAssertEqual(HotkeyFormatter.keyName(keyCode: 999), "Key 999")
    }

    func testValidityRequiresNonShiftModifierAndKnownKey() {
        XCTAssertTrue(HotkeyFormatter.isValid(keyCode: kVK_ANSI_V, carbonModifiers: cmdKey))
        XCTAssertTrue(HotkeyFormatter.isValid(keyCode: kVK_F1, carbonModifiers: controlKey))
        XCTAssertTrue(HotkeyFormatter.isValid(keyCode: kVK_ANSI_V, carbonModifiers: controlKey | optionKey | cmdKey))
        // Shift alone, or no modifier, is not a usable global hotkey.
        XCTAssertFalse(HotkeyFormatter.isValid(keyCode: kVK_ANSI_V, carbonModifiers: shiftKey))
        XCTAssertFalse(HotkeyFormatter.isValid(keyCode: kVK_ANSI_V, carbonModifiers: 0))
        // Unknown key is not valid.
        XCTAssertFalse(HotkeyFormatter.isValid(keyCode: 999, carbonModifiers: cmdKey))
    }
}
