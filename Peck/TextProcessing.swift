import Foundation

/// The action `Typist` takes for a single character. Splitting this classification
/// out from `Typist` (which needs CGEvent / a live event source) lets us unit-test
/// the newline/tab/CRLF dispatch rules as pure logic.
enum TypedKey: Equatable {
    case returnKey
    case tab
    case literal(Character)
}

/// A single step in a typing plan. Beyond plain keys, a plan can inject the
/// Escape key (for bracketed-paste markers) or a "select back to line start"
/// chord (to overwrite an editor's auto-indent).
enum TypingInstruction: Equatable {
    case key(TypedKey)
    case escape          // the physical Escape key (keycode 53)
    case selectLineStart // Shift+Cmd+Left: select the auto-indent, to be typed over
}

/// How to defeat a target's auto-indent when typing multi-line text. Both are
/// opt-in and target-specific — the default types the clipboard verbatim.
enum IndentWorkaround: Int {
    case none = 0
    /// Wrap the text in bracketed-paste markers (ESC[200~ … ESC[201~) so a
    /// terminal/vim/readline treats it as a paste: no auto-indent, and multi-line
    /// input isn't executed line-by-line.
    case bracketedPaste = 1
    /// After each Return, select back to the start of the line so the editor's
    /// auto-indent is replaced by the text's real indentation. For GUI code editors.
    case overwriteIndent = 2
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
        var keys = contentKeys(for: text)
        if appendReturn {
            keys.append(.returnKey)
        }
        return keys
    }

    /// Classify each character, dropping control characters that must never be
    /// typed. C0 controls (tab and the newline set are classified first, so they
    /// never reach the filter), DEL, and C1 controls have no keycode mapping and
    /// would be unicode-injected verbatim — and a raw ESC or one-byte CSI
    /// (U+009B) hidden in copied text could close the bracketed-paste wrapper
    /// early, smuggling keystrokes past the very guard it provides (the
    /// paste-injection attack terminals sanitize against).
    private static func contentKeys(for text: String) -> [TypedKey] {
        text.compactMap { character in
            let key = classify(character)
            if case .literal = key, isDisallowedControl(character) {
                return nil
            }
            return key
        }
    }

    private static func isDisallowedControl(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else { return false }
        // C0 controls, DEL, and C1 controls (raw ESC, the one-byte CSI, etc.).
        if scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) { return true }
        // Invisible Unicode format / bidirectional controls — the "Trojan Source" class:
        // zero-width joiners/spaces, LRM/RLM, bidi embeddings/overrides/isolates,
        // BOM/ZWNBSP. Typed verbatim, they let a clipboard's *visible* text differ from
        // what actually lands in the console (a what-you-see-isn't-what-you-type gap on a
        // root-console paste tool). The guard on a single scalar means multi-scalar emoji
        // that legitimately embed a ZWJ (e.g. 👨‍👩‍👧) are unaffected.
        if scalar.properties.generalCategory == .format { return true }
        return false
    }

    /// How many characters `Typist` will actually type for `rawText`: line breaks
    /// normalized, one trailing newline optionally stripped, and control characters
    /// that are silently dropped removed. The large-paste guardrail counts and shows
    /// this rather than the raw grapheme count, so a clipboard padded with control
    /// bytes can't inflate the "Type N characters?" figure past what really gets typed.
    static func typedCharacterCount(for rawText: String, stripTrailingNewline: Bool) -> Int {
        let text = preparedText(for: rawText, stripTrailingNewline: stripTrailingNewline)
        return contentKeys(for: text).count
    }

    /// The full ordered plan `Typist` executes, incorporating the auto-indent
    /// workaround. `.none` is exactly `keySequence` wrapped as `.key`s.
    static func typingPlan(for rawText: String,
                           workaround: IndentWorkaround,
                           stripTrailingNewline: Bool,
                           appendReturn: Bool) -> [TypingInstruction] {
        let text = preparedText(for: rawText, stripTrailingNewline: stripTrailingNewline)
        let content = contentKeys(for: text)

        // Nothing to type (and no Return to append) → empty plan, so bracketed-paste
        // markers aren't emitted around empty content.
        if content.isEmpty && !appendReturn {
            return []
        }

        var plan: [TypingInstruction] = []
        switch workaround {
        case .none:
            plan = content.map { .key($0) }
        case .bracketedPaste:
            plan += bracketedPasteMarker(open: true)
            plan += content.map { .key($0) }
            plan += bracketedPasteMarker(open: false)
        case .overwriteIndent:
            for key in content {
                plan.append(.key(key))
                if key == .returnKey {
                    plan.append(.selectLineStart)
                }
            }
        }

        if appendReturn {
            // The trailing Return executes/finalizes — for bracketed paste it lands
            // *after* the closing marker, so a shell runs the pasted command.
            plan.append(.key(.returnKey))
        }
        return plan
    }

    /// ESC [ 2 0 0 ~ (open) or ESC [ 2 0 1 ~ (close). Exposed so `Typist` can re-emit the
    /// closing marker when a bracketed-paste run is aborted after the opening marker —
    /// otherwise the target terminal is left stuck in bracketed-paste-receiving mode,
    /// silently buffering everything the user types next.
    static func bracketedPasteMarker(open: Bool) -> [TypingInstruction] {
        let third: Character = open ? "0" : "1"
        return [.escape,
                .key(.literal("[")), .key(.literal("2")), .key(.literal("0")),
                .key(.literal(third)), .key(.literal("~"))]
    }

    /// Number of instructions in one bracketed-paste marker (ESC [ 2 0 x ~ = 6). `Typist`
    /// uses this to know when the opening marker has been fully posted.
    static let bracketedPasteMarkerLength = 6

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
    /// Collapse every line-break convention (CRLF, CR, LF, NEL, LS, PS) to a single `\n`.
    /// One scalar pass instead of five chained `replacingOccurrences` scans — this runs
    /// several times per paste, so the extra allocations added up. A lone CR emits one
    /// newline and, if immediately followed by LF, that LF is swallowed so CRLF stays one.
    static func normalizedLineBreaks(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r":
                result.append("\n")
                lastWasCarriageReturn = true
            case "\n":
                // The LF half of a CRLF: the CR already emitted the newline.
                if lastWasCarriageReturn {
                    lastWasCarriageReturn = false
                } else {
                    result.append("\n")
                }
            case "\u{0085}", "\u{2028}", "\u{2029}":
                result.append("\n")
                lastWasCarriageReturn = false
            default:
                result.unicodeScalars.append(scalar)
                lastWasCarriageReturn = false
            }
        }
        return result
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
