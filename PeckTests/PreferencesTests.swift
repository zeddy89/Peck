import XCTest

/// Exercises defaults registration, mutation round-trips, and persistence across
/// `Preferences` instances — all against a throwaway UserDefaults suite so the
/// real `.standard` domain is never touched.
final class PreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        // Unique-per-test suite name (no Date/random available: use the test name).
        suiteName = "dev.homelab.peck.tests." + name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaults() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.preTypeDelayMs, 400)
        XCTAssertEqual(prefs.keystrokeDelayMs, 15)
        XCTAssertEqual(prefs.typingMode, .keycodes)
        XCTAssertTrue(prefs.hotkeyEnabled)
        XCTAssertEqual(prefs.hotkeyKeyCode, Preferences.HotkeyDefault.keyCode)
        XCTAssertEqual(prefs.hotkeyCarbonModifiers, Preferences.HotkeyDefault.carbonModifiers)
        XCTAssertEqual(prefs.largePasteThreshold, 1000)
        XCTAssertFalse(prefs.pressReturnAfterTyping)
        XCTAssertTrue(prefs.stripTrailingNewline)
    }

    func testNewSettingsRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.hotkeyKeyCode = 40
        prefs.hotkeyCarbonModifiers = 256
        prefs.largePasteThreshold = 0
        prefs.pressReturnAfterTyping = true
        prefs.stripTrailingNewline = false

        let reader = Preferences(defaults: defaults)
        XCTAssertEqual(reader.hotkeyKeyCode, 40)
        XCTAssertEqual(reader.hotkeyCarbonModifiers, 256)
        XCTAssertEqual(reader.largePasteThreshold, 0)
        XCTAssertTrue(reader.pressReturnAfterTyping)
        XCTAssertFalse(reader.stripTrailingNewline)
    }

    func testMutationRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.preTypeDelayMs = 800
        prefs.keystrokeDelayMs = 30
        prefs.typingMode = .unicode
        prefs.hotkeyEnabled = false

        XCTAssertEqual(prefs.preTypeDelayMs, 800)
        XCTAssertEqual(prefs.keystrokeDelayMs, 30)
        XCTAssertEqual(prefs.typingMode, .unicode)
        XCTAssertFalse(prefs.hotkeyEnabled)
    }

    func testPersistenceAcrossInstances() {
        let writer = Preferences(defaults: defaults)
        writer.preTypeDelayMs = 750
        writer.typingMode = .unicode

        // A fresh instance on the same suite sees the persisted values.
        let reader = Preferences(defaults: defaults)
        XCTAssertEqual(reader.preTypeDelayMs, 750)
        XCTAssertEqual(reader.typingMode, .unicode)
    }

    func testTypingModeFallsBackToKeycodesForUnknownRawValue() {
        defaults.set(999, forKey: "typingMode")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.typingMode, .keycodes)
    }
}
