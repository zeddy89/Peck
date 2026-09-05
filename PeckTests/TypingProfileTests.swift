import XCTest

final class TypingProfileTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var prefs: Preferences!
    override func setUp() {
        suite = "dev.homelab.peck.profile-tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        prefs = Preferences(defaults: defaults)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func validData() throws -> Data {
        try TypingProfile(name: "Lab", notes: "User-provided test notes", settings: ProfileSettings(preferences: prefs)).encoded()
    }
    private func changed(_ mutation: (inout [String: Any]) -> Void) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: validData()) as! [String: Any]
        mutation(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }
    func testRoundTripPreservesPortableSettingsButNotPrivateOrHostState() throws {
        prefs.apply(.vimBracketed)
        let data = try validData()
        let profile = try TypingProfile.decode(data)
        XCTAssertEqual(profile.settings, ProfileSettings(preferences: prefs))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "name", "notes", "settings"])
        let settings = object["settings"] as! [String: Any]
        XCTAssertEqual(Set(settings.keys), Set(ProfileSettings.CodingKeys.allCases.map(\.rawValue)))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("hotkey"))
        let originalKey = prefs.hotkeyKeyCode
        let originalFocusKey = prefs.currentFocusHotkeyKeyCode
        try profile.settings.apply(to: prefs)
        XCTAssertEqual(prefs.hotkeyKeyCode, originalKey)
        XCTAssertEqual(prefs.currentFocusHotkeyKeyCode, originalFocusKey)
    }
    func testUnknownRootAndNestedFieldsAreRejected() throws {
        XCTAssertThrowsError(try TypingProfile.decode(changed { $0["password"] = "must not be accepted" }))
        XCTAssertThrowsError(try TypingProfile.decode(changed {
            var settings = $0["settings"] as! [String: Any]
            settings["launchAtLogin"] = true
            $0["settings"] = settings
        }))
    }
    func testSchemaEnumsMissingAndWrongTypesAreRejected() throws {
        XCTAssertThrowsError(try TypingProfile.decode(changed { $0["schemaVersion"] = 2 }))
        for (key, value) in [("typingMode", 99 as Any), ("indentWorkaround", 99 as Any),
                              ("warnOnReturn", "true" as Any), ("keyHoldMs", NSNull())] {
            XCTAssertThrowsError(try TypingProfile.decode(changed {
                var settings = $0["settings"] as! [String: Any]
                settings[key] = value
                $0["settings"] = settings
            }))
        }
        XCTAssertThrowsError(try TypingProfile.decode(changed {
            var settings = $0["settings"] as! [String: Any]
            settings.removeValue(forKey: "stripTrailingNewline")
            $0["settings"] = settings
        }))
    }
    func testBoundsAreRejectedBeforeAnyPreferencesMutation() throws {
        let original = ProfileSettings(preferences: prefs)
        for bad in [-1, 101, Int.max] {
            var settings = original
            settings.preTypeDelayMs = 123
            settings.keyHoldMs = bad
            XCTAssertThrowsError(try settings.apply(to: prefs))
            XCTAssertEqual(ProfileSettings(preferences: prefs), original)
        }
        XCTAssertThrowsError(try TypingProfile.decode(Data(repeating: 32, count: TypingProfile.maximumBytes + 1)))
        XCTAssertThrowsError(try TypingProfile(name: String(repeating: "x", count: 161), settings: original))
        XCTAssertThrowsError(try TypingProfile(notes: String(repeating: "x", count: 2001), settings: original))
        XCTAssertThrowsError(try TypingProfile(name: "line\nbreak", settings: original))
    }
    func testSummaryIncludesEverySafetySetting() {
        var settings = ProfileSettings(preferences: prefs)
        settings.warnOnReturn = false
        settings.strictKeycodes = false
        settings.pressReturnAfterTyping = true
        settings.indentWorkaround = 1
        settings.largePasteThreshold = 0
        XCTAssertTrue(settings.summary.contains("warn on Return: Off"))
        XCTAssertTrue(settings.summary.contains("Strict keycodes: Off"))
        XCTAssertTrue(settings.summary.contains("Append Return: On"))
        XCTAssertTrue(settings.summary.contains("Bracketed paste"))
        XCTAssertTrue(settings.summary.contains("Size warning: Disabled"))
        XCTAssertTrue(settings.summary.contains("Paste confirmation: Off (Return/size rules inactive)"))
    }
    func testMasterConfirmationRoundTripAndOldProfileCompatibility() throws {
        prefs.confirmBeforeTyping = true
        let current = try TypingProfile.decode(validData())
        XCTAssertTrue(current.settings.confirmBeforeTyping)
        XCTAssertTrue(current.settings.summary.contains("Paste confirmation: On when a warning applies"))
        let old = try TypingProfile.decode(changed {
            var settings = $0["settings"] as! [String: Any]
            settings.removeValue(forKey: "confirmBeforeTyping")
            $0["settings"] = settings
        })
        XCTAssertFalse(old.settings.confirmBeforeTyping)
        try old.settings.apply(to: prefs)
        XCTAssertFalse(prefs.confirmBeforeTyping)
        try current.settings.apply(to: prefs)
        XCTAssertTrue(prefs.confirmBeforeTyping)
    }
    func testMalformedMasterConfirmationIsRejectedBeforeMutation() throws {
        prefs.confirmBeforeTyping = true
        let before = ProfileSettings(preferences: prefs)
        for value: Any in ["false", NSNull(), 1] {
            XCTAssertThrowsError(try TypingProfile.decode(changed {
                var settings = $0["settings"] as! [String: Any]
                settings["confirmBeforeTyping"] = value
                $0["settings"] = settings
            }))
            XCTAssertEqual(ProfileSettings(preferences: prefs), before)
        }
    }
    func testReadBoundsAndRejectsNonRegularFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("profile.json")
        try validData().write(to: file)
        XCTAssertEqual(try TypingProfile.read(from: file).name, "Lab")
        XCTAssertThrowsError(try TypingProfile.read(from: directory))
        try Data(repeating: 32, count: 100000).write(to: file)
        XCTAssertThrowsError(try TypingProfile.read(from: file))
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try TypingProfile.read(from: link))
    }
}
