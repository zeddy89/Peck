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
        XCTAssertEqual(prefs.keystrokeDelayMs, 2)
        XCTAssertEqual(prefs.speedChoice, .fast)
        XCTAssertFalse(prefs.confirmBeforeTyping)
        XCTAssertEqual(prefs.typingMode, .keycodes)
        XCTAssertTrue(prefs.hotkeyEnabled)
        XCTAssertEqual(prefs.hotkeyKeyCode, Preferences.HotkeyDefault.keyCode)
        XCTAssertEqual(prefs.hotkeyCarbonModifiers, Preferences.HotkeyDefault.carbonModifiers)
        XCTAssertEqual(prefs.largePasteThreshold, 1000)
        XCTAssertFalse(prefs.pressReturnAfterTyping)
        XCTAssertTrue(prefs.stripTrailingNewline)
        XCTAssertEqual(prefs.indentWorkaround, .none)
    }

    func testIndentWorkaroundRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.indentWorkaround = .bracketedPaste
        XCTAssertEqual(Preferences(defaults: defaults).indentWorkaround, .bracketedPaste)
        prefs.indentWorkaround = .overwriteIndent
        XCTAssertEqual(Preferences(defaults: defaults).indentWorkaround, .overwriteIndent)
    }

    func testIndentWorkaroundFallsBackForUnknownRawValue() {
        defaults.set(999, forKey: "indentWorkaround")
        XCTAssertEqual(Preferences(defaults: defaults).indentWorkaround, .none)
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
    func testUpgradePreservesExistingSettingsAndCustomDoesNothing() {
        defaults.set(2, forKey: "indentWorkaround")
        defaults.set(730, forKey: "preTypeDelayMs")
        defaults.set(21, forKey: "keystrokeDelayMs")
        let prefs = Preferences(defaults: defaults)
        prefs.apply(.custom)
        XCTAssertEqual(prefs.indentWorkaround, .overwriteIndent)
        XCTAssertEqual(prefs.preTypeDelayMs, 730)
        XCTAssertEqual(prefs.keystrokeDelayMs, 21)
        XCTAssertTrue(prefs.warnOnReturn)
        XCTAssertFalse(prefs.strictKeycodes)
        XCTAssertEqual(prefs.keyHoldMs, 0)
        XCTAssertFalse(prefs.confirmBeforeTyping)
        XCTAssertNil(prefs.speedChoice)
    }

    func testConservativePresetIsExplicit() {
        let prefs = Preferences(defaults: defaults)
        prefs.indentWorkaround = .overwriteIndent
        prefs.apply(.conservative)
        XCTAssertEqual(prefs.indentWorkaround, .none)
        XCTAssertEqual(prefs.typingMode, .keycodes)
        XCTAssertEqual(prefs.preTypeDelayMs, 1000)
        XCTAssertEqual(prefs.keystrokeDelayMs, 40)
        XCTAssertEqual(prefs.keyHoldMs, 10)
        XCTAssertEqual(prefs.newlineDelayMs, 150)
        XCTAssertTrue(prefs.strictKeycodes)
        XCTAssertTrue(prefs.warnOnReturn)
        XCTAssertFalse(prefs.pressReturnAfterTyping)
        prefs.apply(.native)
        XCTAssertEqual(prefs.typingMode, .unicode)
        XCTAssertFalse(prefs.strictKeycodes)
    }

    func testTimingBoundsIncludingPersistedOutOfRangeValues() {
        let prefs = Preferences(defaults: defaults)
        prefs.keyHoldMs = 9999
        prefs.newlineDelayMs = -1
        prefs.preTypeDelayMs = 999999
        defaults.set(-123, forKey: "keystrokeDelayMs")
        XCTAssertEqual(prefs.keyHoldMs, 100)
        XCTAssertEqual(prefs.newlineDelayMs, 0)
        XCTAssertEqual(prefs.preTypeDelayMs, 10000)
        XCTAssertEqual(prefs.keystrokeDelayMs, 0)
    }

    func testFastConsolePresetDoesNotRetainConservativeDelays() {
        let prefs = Preferences(defaults: defaults)
        prefs.apply(.conservative)
        prefs.apply(.console)
        XCTAssertEqual(prefs.keystrokeDelayMs, 2)
        XCTAssertEqual(prefs.keyHoldMs, 0)
        XCTAssertEqual(prefs.newlineDelayMs, 0)
        XCTAssertEqual(prefs.preTypeDelayMs, 600)
        XCTAssertEqual(prefs.indentWorkaround, .none)
    }

    func testCurrentFocusDefaultDistinctAndBracketedPresetExplicit() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.currentFocusHotkeyEnabled)
        XCTAssertEqual(prefs.currentFocusHotkeyKeyCode, prefs.hotkeyKeyCode)
        XCTAssertNotEqual(prefs.currentFocusHotkeyModifiers, prefs.hotkeyCarbonModifiers)
        prefs.apply(.vimBracketed)
        XCTAssertEqual(prefs.indentWorkaround, .bracketedPaste)
        XCTAssertTrue(prefs.warnOnReturn)
        XCTAssertTrue(prefs.strictKeycodes)
    }

    func testSpeedChoicesChangeOnlyCharacterDelayAndReflectCustomSettings() {
        let prefs = Preferences(defaults: defaults)
        prefs.keyHoldMs = 10
        prefs.newlineDelayMs = 150
        prefs.preTypeDelayMs = 731
        prefs.confirmBeforeTyping = true
        for (choice, delay) in [(Preferences.SpeedChoice.fast, 2), (.medium, 5), (.slow, 15)] {
            prefs.applySpeed(choice)
            XCTAssertEqual(prefs.keystrokeDelayMs, delay)
            XCTAssertEqual(prefs.speedChoice, choice)
            XCTAssertEqual(prefs.keyHoldMs, 10)
            XCTAssertEqual(prefs.newlineDelayMs, 150)
            XCTAssertEqual(prefs.preTypeDelayMs, 731)
            XCTAssertTrue(prefs.confirmBeforeTyping)
        }
        prefs.keystrokeDelayMs = 7
        XCTAssertNil(prefs.speedChoice)
    }

    func testSavedSlowAndCustomTimingsAreNotMigratedToFast() {
        for delay in [15, 7, 2] {
            defaults.set(delay, forKey: "keystrokeDelayMs")
            defaults.set(true, forKey: "warnOnReturn")
            defaults.set(1000, forKey: "largePasteThreshold")
            let prefs = Preferences(defaults: defaults)
            XCTAssertEqual(prefs.keystrokeDelayMs, delay)
            XCTAssertFalse(prefs.confirmBeforeTyping)
        }
    }

    func testPresetsNeverSilentlyEnableOrDisableMasterConfirmation() {
        let prefs = Preferences(defaults: defaults)
        for enabled in [false, true] {
            prefs.confirmBeforeTyping = enabled
            for preset in Preferences.Preset.allCases {
                prefs.apply(preset)
                XCTAssertEqual(prefs.confirmBeforeTyping, enabled)
            }
        }
        XCTAssertTrue(Preferences(defaults: defaults).confirmBeforeTyping)
    }

    func testDefaultLargeMultilinePlanDoesNotRequestRoutineConfirmation() {
        let prefs = Preferences(defaults: defaults)
        let text = String(repeating: "test\n", count: 300)
        let plan = TextProcessing.typingPlan(for: text, workaround: .none,
            stripTrailingNewline: false, appendReturn: true)
        let count = TextProcessing.typedCharacterCount(for: text, stripTrailingNewline: false)
        XCTAssertGreaterThan(count, prefs.largePasteThreshold)
        XCTAssertGreaterThan(PasteSafety.returnCount(in: plan), 0)
        XCTAssertFalse(PasteSafety.shouldConfirm(typedCount: count, returns: PasteSafety.returnCount(in: plan),
            confirmationEnabled: prefs.confirmBeforeTyping, warnOnReturn: prefs.warnOnReturn,
            threshold: prefs.largePasteThreshold))
    }

    func testOptInConfirmationRespectsWarningRulesAndBoundaries() {
        XCTAssertTrue(PasteSafety.shouldConfirm(typedCount: 5, returns: 1,
            confirmationEnabled: true, warnOnReturn: true, threshold: 1000))
        XCTAssertFalse(PasteSafety.shouldConfirm(typedCount: 1000, returns: 0,
            confirmationEnabled: true, warnOnReturn: true, threshold: 1000))
        XCTAssertTrue(PasteSafety.shouldConfirm(typedCount: 1001, returns: 0,
            confirmationEnabled: true, warnOnReturn: false, threshold: 1000))
        XCTAssertFalse(PasteSafety.shouldConfirm(typedCount: 1001, returns: 10,
            confirmationEnabled: true, warnOnReturn: false, threshold: 0))
        XCTAssertFalse(PasteSafety.shouldConfirm(typedCount: 1001, returns: 10,
            confirmationEnabled: false, warnOnReturn: true, threshold: 1000))
    }

}
