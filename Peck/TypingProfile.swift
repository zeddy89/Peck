import Foundation
import Darwin

private struct ProfileKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func requireKnownKeys(_ decoder: Decoder, names: Set<String>) throws {
    let container = try decoder.container(keyedBy: ProfileKey.self)
    guard Set(container.allKeys.map(\.stringValue)).isSubset(of: names) else {
        throw ProfileError.invalid("Unknown profile fields are not supported.")
    }
}

enum ProfileError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

/// Portable settings only. Hotkeys, login registration, clipboard contents,
/// receiving text and calibration history are deliberately outside this schema.
struct ProfileSettings: Codable, Equatable {
    var preTypeDelayMs: Int
    var keystrokeDelayMs: Int
    var keyHoldMs: Int
    var newlineDelayMs: Int
    var typingMode: Int
    var indentWorkaround: Int
    var strictKeycodes: Bool
    var warnOnReturn: Bool
    var confirmBeforeTyping: Bool
    var pressReturnAfterTyping: Bool
    var stripTrailingNewline: Bool
    var largePasteThreshold: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case preTypeDelayMs, keystrokeDelayMs, keyHoldMs, newlineDelayMs
        case typingMode, indentWorkaround, strictKeycodes, warnOnReturn, confirmBeforeTyping
        case pressReturnAfterTyping, stripTrailingNewline, largePasteThreshold
    }
    init(preferences: Preferences) {
        preTypeDelayMs = preferences.preTypeDelayMs
        keystrokeDelayMs = preferences.keystrokeDelayMs
        keyHoldMs = preferences.keyHoldMs
        newlineDelayMs = preferences.newlineDelayMs
        typingMode = preferences.typingMode.rawValue
        indentWorkaround = preferences.indentWorkaround.rawValue
        strictKeycodes = preferences.strictKeycodes
        warnOnReturn = preferences.warnOnReturn
        confirmBeforeTyping = preferences.confirmBeforeTyping
        pressReturnAfterTyping = preferences.pressReturnAfterTyping
        stripTrailingNewline = preferences.stripTrailingNewline
        largePasteThreshold = preferences.largePasteThreshold
    }
    init(from decoder: Decoder) throws {
        try requireKnownKeys(decoder, names: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preTypeDelayMs = try c.decode(Int.self, forKey: .preTypeDelayMs)
        keystrokeDelayMs = try c.decode(Int.self, forKey: .keystrokeDelayMs)
        keyHoldMs = try c.decode(Int.self, forKey: .keyHoldMs)
        newlineDelayMs = try c.decode(Int.self, forKey: .newlineDelayMs)
        typingMode = try c.decode(Int.self, forKey: .typingMode)
        indentWorkaround = try c.decode(Int.self, forKey: .indentWorkaround)
        strictKeycodes = try c.decode(Bool.self, forKey: .strictKeycodes)
        warnOnReturn = try c.decode(Bool.self, forKey: .warnOnReturn)
        // Schema-1 profiles from 1.3 predate this opt-in master. Preserve the new
        // no-routine-popup default when importing one, but reject malformed values.
        if c.contains(.confirmBeforeTyping) {
            confirmBeforeTyping = try c.decode(Bool.self, forKey: .confirmBeforeTyping)
        } else {
            confirmBeforeTyping = false
        }
        pressReturnAfterTyping = try c.decode(Bool.self, forKey: .pressReturnAfterTyping)
        stripTrailingNewline = try c.decode(Bool.self, forKey: .stripTrailingNewline)
        largePasteThreshold = try c.decode(Int.self, forKey: .largePasteThreshold)
        try validated()
    }
    func validated() throws {
        guard (0...10000).contains(preTypeDelayMs), (0...10000).contains(keystrokeDelayMs),
              (0...100).contains(keyHoldMs), (0...10000).contains(newlineDelayMs),
              (0...10000000).contains(largePasteThreshold),
              Preferences.TypingMode(rawValue: typingMode) != nil,
              IndentWorkaround(rawValue: indentWorkaround) != nil else {
            throw ProfileError.invalid("Profile contains an unknown mode or out-of-range setting.")
        }
    }
    func apply(to preferences: Preferences) throws {
        try validated() // Validate every field before the first mutation.
        preferences.preTypeDelayMs = preTypeDelayMs
        preferences.keystrokeDelayMs = keystrokeDelayMs
        preferences.keyHoldMs = keyHoldMs
        preferences.newlineDelayMs = newlineDelayMs
        preferences.typingMode = Preferences.TypingMode(rawValue: typingMode)!
        preferences.indentWorkaround = IndentWorkaround(rawValue: indentWorkaround)!
        preferences.strictKeycodes = strictKeycodes
        preferences.warnOnReturn = warnOnReturn
        preferences.confirmBeforeTyping = confirmBeforeTyping
        preferences.pressReturnAfterTyping = pressReturnAfterTyping
        preferences.stripTrailingNewline = stripTrailingNewline
        preferences.largePasteThreshold = largePasteThreshold
    }
    var summary: String {
        let mode = typingMode == 0 ? "Keycodes" : "Unicode"
        let indent = ["Off", "Bracketed paste (requires target support)", "Overwrite indent (macOS editors only)"]
        let workaround = indent.indices.contains(indentWorkaround) ? indent[indentWorkaround] : "Invalid"
        func state(_ value: Bool) -> String { value ? "On" : "Off" }
        return """
        Mode: \(mode); auto-indent workaround: \(workaround)
        Focus delay: \(preTypeDelayMs) ms; character delay: \(keystrokeDelayMs) ms
        Key hold: \(keyHoldMs) ms; extra Return delay: \(newlineDelayMs) ms
        Strict keycodes: \(state(strictKeycodes)); warn on Return: \(state(warnOnReturn))
        Paste confirmation: \(confirmBeforeTyping ? "On when a warning applies" : "Off (Return/size rules inactive)")
        Append Return: \(state(pressReturnAfterTyping)); strip one trailing newline: \(state(stripTrailingNewline))
        Size warning: \(largePasteThreshold == 0 ? "Disabled" : "over \(largePasteThreshold) characters")
        """
    }
}

struct TypingProfile: Codable, Equatable {
    static let maximumBytes = 16384
    let schemaVersion: Int
    var name: String?
    var notes: String?
    let settings: ProfileSettings
    enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, name, notes, settings }

    init(name: String? = nil, notes: String? = nil, settings: ProfileSettings) throws {
        schemaVersion = 1
        self.name = name
        self.notes = notes
        self.settings = settings
        try validated()
    }
    init(from decoder: Decoder) throws {
        try requireKnownKeys(decoder, names: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        settings = try c.decode(ProfileSettings.self, forKey: .settings)
        try validated()
    }
    func validated() throws {
        guard schemaVersion == 1 else { throw ProfileError.invalid("Unsupported profile schema version.") }
        for (text, maximum, permitsNewlines) in [(name, 160, false), (notes, 2000, true)] {
            guard let text else { continue }
            guard text.utf8.count <= maximum,
                  !text.unicodeScalars.contains(where: {
                      (CharacterSet.controlCharacters.contains($0) && !(permitsNewlines && $0 == "\n"))
                      || $0.properties.generalCategory == .format
                  }) else { throw ProfileError.invalid("Profile name or notes are too long or contain unsupported control characters.") }
        }
        try settings.validated()
    }
    static func decode(_ data: Data) throws -> TypingProfile {
        guard data.count <= maximumBytes else { throw ProfileError.invalid("Profile exceeds the 16 KB limit.") }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    func encoded() throws -> Data {
        try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ProfileError.invalid("Profile exceeds the 16 KB limit.") }
        return data
    }
    static func read(from url: URL) throws -> TypingProfile {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW) } ?? -1
        }
        guard descriptor >= 0 else { throw ProfileError.invalid("Select a readable regular JSON file, not a symbolic link.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw ProfileError.invalid("Profiles must be regular JSON files.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        // Read at most one byte beyond the bound, even for huge selected files.
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try decode(data)
    }
}
