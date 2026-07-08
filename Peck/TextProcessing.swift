import Foundation

/// The action `Typist` takes for a single character. Splitting this classification
/// out from `Typist` (which needs CGEvent / a live event source) lets us unit-test
/// the newline/tab/CRLF dispatch rules as pure logic.
enum TypedKey: Equatable {
    case returnKey
    case tab
    case literal(Character)
}

enum TextProcessing {

    /// Classify a single character into the key action `Typist` will emit.
    ///
    /// Note that `"\r\n"` is a *single* Swift `Character` (an extended grapheme
    /// cluster), so a bare CRLF that slipped past normalization still maps to
    /// exactly one Return here.
    static func classify(_ character: Character) -> TypedKey {
        switch character {
        case "\r\n", "\n", "\r", "\u{0085}", "\u{2028}", "\u{2029}":
            return .returnKey
        case "\t":
            return .tab
        default:
            return .literal(character)
        }
    }

    /// The full ordered sequence of key actions `Typist.type` will emit for a raw
    /// string: normalize line breaks, optionally strip a single trailing newline,
    /// classify each `Character`, and optionally append a trailing Return.
    ///
    /// This mirrors the real dispatch loop exactly, so a test can assert that e.g.
    /// `"a\r\nb"` yields `[.literal("a"), .returnKey, .literal("b")]` — one Return.
    static func keySequence(for rawText: String,
                            stripTrailingNewline: Bool = false,
                            appendReturn: Bool = false) -> [TypedKey] {
        let text = preparedText(for: rawText, stripTrailingNewline: stripTrailingNewline)
        var keys = text.map(classify)
        if appendReturn {
            keys.append(.returnKey)
        }
        return keys
    }

    /// The text `Typist` will actually iterate: normalized line breaks, with a
    /// single trailing newline optionally removed. Terminal copies almost always
    /// drag one trailing newline along, and in a console that newline executes the
    /// last command, so stripping it is the safe default.
    static func preparedText(for rawText: String, stripTrailingNewline: Bool) -> String {
        var text = TextNormalizer.normalizedLineBreaks(rawText)
        if stripTrailingNewline, text.hasSuffix("\n") {
            text.removeLast()
        }
        return text
    }
}

enum TextNormalizer {
    static func normalizedLineBreaks(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\u{0085}", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\u{2028}", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\u{2029}", with: "\n")
        return normalized
    }

    static func lineBreakCount(in text: String) -> Int {
        normalizedLineBreaks(text).reduce(0) { count, character in
            character == "\n" ? count + 1 : count
        }
    }

    static func sameWords(_ lhs: String, _ rhs: String) -> Bool {
        wordFingerprint(lhs) == wordFingerprint(rhs)
    }

    private static func wordFingerprint(_ text: String) -> [String] {
        let folded = normalizedLineBreaks(text).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        var words: [String] = []
        var current = ""

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            words.append(current)
        }

        return words
    }
}
