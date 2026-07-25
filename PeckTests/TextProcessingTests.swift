import XCTest

/// Covers the newline/tab/CRLF dispatch rules that decide what `Typist` presses,
/// plus the trailing-newline / trailing-Return text preparation.
final class TextProcessingTests: XCTestCase {

    // MARK: - classify

    func testClassifyNewlineVariantsAreReturn() {
        for ch in ["\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}"] {
            XCTAssertEqual(TextProcessing.classify(Character(ch)), .returnKey, "\(ch.debugDescription) should be Return")
        }
    }

    func testClassifyTab() {
        XCTAssertEqual(TextProcessing.classify("\t"), .tab)
    }

    func testClassifyLiteral() {
        XCTAssertEqual(TextProcessing.classify("a"), .literal("a"))
        XCTAssertEqual(TextProcessing.classify("Z"), .literal("Z"))
        XCTAssertEqual(TextProcessing.classify(" "), .literal(" "))
        XCTAssertEqual(TextProcessing.classify("é"), .literal("é"))
    }

    // MARK: - CRLF is a single grapheme

    func testCRLFIsOneSwiftCharacter() {
        // The whole reason "\r\n" needs its own case: Swift treats it as one Character.
        XCTAssertEqual(Array("a\r\nb").count, 3)
        XCTAssertEqual(Array("a\r\nb")[1], "\r\n")
    }

    func testCRLFProducesExactlyOneReturn() {
        let keys = TextProcessing.keySequence(for: "a\r\nb")
        XCTAssertEqual(keys, [.literal("a"), .returnKey, .literal("b")])
    }

    func testDoubleCRLFProducesTwoReturns() {
        let keys = TextProcessing.keySequence(for: "a\r\n\r\nb")
        XCTAssertEqual(keys, [.literal("a"), .returnKey, .returnKey, .literal("b")])
    }

    // MARK: - keySequence

    func testTabDispatch() {
        XCTAssertEqual(TextProcessing.keySequence(for: "x\ty"), [.literal("x"), .tab, .literal("y")])
    }

    func testReturnCountMatchesLines() {
        let keys = TextProcessing.keySequence(for: "line1\nline2\nline3")
        XCTAssertEqual(keys.filter { $0 == .returnKey }.count, 2)
    }

    func testMixedNewlinesCollapseToReturns() {
        // Mac-classic CR, Windows CRLF, and Unix LF all become a single Return each.
        let keys = TextProcessing.keySequence(for: "a\rb\r\nc\nd")
        XCTAssertEqual(keys, [
            .literal("a"), .returnKey,
            .literal("b"), .returnKey,
            .literal("c"), .returnKey,
            .literal("d"),
        ])
    }

    // MARK: - Trailing newline / trailing Return

    func testStripTrailingNewlineRemovesExactlyOne() {
        XCTAssertEqual(TextProcessing.preparedText(for: "cmd\n", stripTrailingNewline: true), "cmd")
        XCTAssertEqual(TextProcessing.preparedText(for: "cmd\r\n", stripTrailingNewline: true), "cmd")
        // Only one is stripped, so a blank line before EOF survives.
        XCTAssertEqual(TextProcessing.preparedText(for: "cmd\n\n", stripTrailingNewline: true), "cmd\n")
    }

    func testStripTrailingNewlineDropsTrailingReturnKey() {
        let keys = TextProcessing.keySequence(for: "reboot\n", stripTrailingNewline: true)
        XCTAssertEqual(keys, [.literal("r"), .literal("e"), .literal("b"), .literal("o"), .literal("o"), .literal("t")])
    }

    func testStripTrailingNewlineOnTextWithoutOneIsNoop() {
        XCTAssertEqual(TextProcessing.preparedText(for: "cmd", stripTrailingNewline: true), "cmd")
    }

    func testAppendReturnAddsOneReturnAtEnd() {
        let keys = TextProcessing.keySequence(for: "hi", appendReturn: true)
        XCTAssertEqual(keys, [.literal("h"), .literal("i"), .returnKey])
    }

    func testStripThenAppendYieldsSingleReturn() {
        // Strip the dragged-along newline, then deliberately append one Return.
        let keys = TextProcessing.keySequence(for: "run\n", stripTrailingNewline: true, appendReturn: true)
        XCTAssertEqual(keys, [.literal("r"), .literal("u"), .literal("n"), .returnKey])
    }

    // MARK: - Control-character sanitization

    func testEscapeIsDropped() {
        XCTAssertEqual(TextProcessing.keySequence(for: "a\u{1B}b"), [.literal("a"), .literal("b")])
    }

    func testC0DELAndC1ControlsAreDropped() {
        // C0 (SOH), DEL, and the one-byte CSI (C1) all vanish; é survives.
        let keys = TextProcessing.keySequence(for: "\u{01}x\u{7F}\u{9B}é")
        XCTAssertEqual(keys, [.literal("x"), .literal("é")])
    }

    func testTabAndNewlinesSurviveSanitization() {
        XCTAssertEqual(TextProcessing.keySequence(for: "a\t\nb"),
                       [.literal("a"), .tab, .returnKey, .literal("b")])
    }

    func testBracketedPasteContentCannotContainEscape() {
        // An ESC[201~ embedded in the clipboard must not close the wrapper early:
        // the ESC literal is dropped, so only Peck's own two markers remain and
        // the rest of the payload is typed as inert text.
        let plan = TextProcessing.typingPlan(for: "x\u{1B}[201~y", workaround: .bracketedPaste,
                                             stripTrailingNewline: false, appendReturn: false)
        XCTAssertEqual(plan.filter { $0 == .escape }.count, 2)
        XCTAssertFalse(plan.contains(.key(.literal("\u{1B}"))))
        XCTAssertFalse(plan.contains(.key(.literal("\u{9B}"))))
    }

    func testOverwriteIndentPlanIsSanitizedToo() {
        // The filter feeds every workaround branch, not just bracketed paste.
        let plan = TextProcessing.typingPlan(for: "a\u{1B}\nb", workaround: .overwriteIndent,
                                             stripTrailingNewline: false, appendReturn: false)
        XCTAssertEqual(plan, [
            .key(.literal("a")),
            .key(.returnKey), .selectLineStart,
            .key(.literal("b")),
        ])
    }

    func testAllControlClipboardYieldsEmptyPlan() {
        let plan = TextProcessing.typingPlan(for: "\u{1B}\u{07}", workaround: .bracketedPaste,
                                             stripTrailingNewline: false, appendReturn: false)
        XCTAssertTrue(plan.isEmpty)
    }

    func testZeroWidthAndBidiFormatControlsAreDropped() {
        // Trojan-Source class: invisible zero-width / bidi format controls (ZWSP,
        // right-to-left override, BOM) never reach the target, so the clipboard's
        // visible text can't differ from what actually gets typed.
        let keys = TextProcessing.keySequence(for: "a\u{200B}b\u{202E}c\u{FEFF}d")
        XCTAssertEqual(keys, [.literal("a"), .literal("b"), .literal("c"), .literal("d")])
    }

    func testEmojiZWJSequenceSurvivesFormatFilter() {
        // A multi-scalar emoji legitimately embeds U+200D ZWJ; the format-control filter
        // only rejects single-scalar characters, so the whole grapheme is typed intact.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" // 👨‍👩‍👧, one Character
        XCTAssertEqual(Array(family).count, 1)
        XCTAssertEqual(TextProcessing.keySequence(for: family), [.literal(Character(family))])
    }

    // MARK: - typedCharacterCount (large-paste guardrail)

    func testTypedCharacterCountExcludesDroppedControls() {
        // 3 visible characters plus control bytes that are never typed → count is 3.
        XCTAssertEqual(TextProcessing.typedCharacterCount(for: "a\u{1B}b\u{7F}c", stripTrailingNewline: false), 3)
    }

    func testTypedCharacterCountCountsNewlinesAndRespectsStrip() {
        // Newlines are typed (as Return) and counted; a stripped trailing newline isn't.
        XCTAssertEqual(TextProcessing.typedCharacterCount(for: "a\nb\n", stripTrailingNewline: false), 4)
        XCTAssertEqual(TextProcessing.typedCharacterCount(for: "a\nb\n", stripTrailingNewline: true), 3)
    }

    // MARK: - Bracketed-paste marker (shared with Typist's abort recovery)

    func testBracketedPasteMarkerHelperMatchesLengthAndContent() {
        XCTAssertEqual(TextProcessing.bracketedPasteMarker(open: true).count,
                       TextProcessing.bracketedPasteMarkerLength)
        XCTAssertEqual(TextProcessing.bracketedPasteMarker(open: false), [
            .escape, .key(.literal("[")), .key(.literal("2")), .key(.literal("0")),
            .key(.literal("1")), .key(.literal("~")),
        ])
    }

    // MARK: - TextNormalizer

    func testNormalizedLineBreaks() {
        XCTAssertEqual(TextNormalizer.normalizedLineBreaks("a\r\nb\rc\u{2028}d"), "a\nb\nc\nd")
    }

    func testNormalizedLineBreaksCollapsesCRLFRunsAndTrailingCR() {
        // The single-pass scan must match the old chained-replace behavior on the tricky
        // adjacencies: consecutive CRLFs, back-to-back CRs, and a CR at the very end.
        XCTAssertEqual(TextNormalizer.normalizedLineBreaks("a\r\n\r\nb"), "a\n\nb")
        XCTAssertEqual(TextNormalizer.normalizedLineBreaks("a\r\rb"), "a\n\nb")
        XCTAssertEqual(TextNormalizer.normalizedLineBreaks("a\r"), "a\n")
        XCTAssertEqual(TextNormalizer.normalizedLineBreaks("a\r\n"), "a\n")
        XCTAssertEqual(TextNormalizer.normalizedLineBreaks("\r\nx"), "\nx")
    }

    func testLineBreakCount() {
        XCTAssertEqual(TextNormalizer.lineBreakCount(in: "a\nb\nc"), 2)
        XCTAssertEqual(TextNormalizer.lineBreakCount(in: "no breaks"), 0)
        XCTAssertEqual(TextNormalizer.lineBreakCount(in: "a\r\nb"), 1)
    }

    func testSameWordsIgnoresCaseDiacriticsAndPunctuation() {
        XCTAssertTrue(TextNormalizer.sameWords("Café résumé!", "cafe resume"))
        XCTAssertFalse(TextNormalizer.sameWords("hello world", "hello there"))
    }

    // MARK: - typingPlan / auto-indent workaround

    func testPlanNoneMatchesPlainKeys() {
        let plan = TextProcessing.typingPlan(for: "a\nb", workaround: .none,
                                             stripTrailingNewline: false, appendReturn: false)
        XCTAssertEqual(plan, [.key(.literal("a")), .key(.returnKey), .key(.literal("b"))])
    }

    func testPlanBracketedPasteWrapsContentInMarkers() {
        let plan = TextProcessing.typingPlan(for: "ab", workaround: .bracketedPaste,
                                             stripTrailingNewline: false, appendReturn: false)
        XCTAssertEqual(plan, [
            // ESC [ 2 0 0 ~
            .escape, .key(.literal("[")), .key(.literal("2")), .key(.literal("0")),
            .key(.literal("0")), .key(.literal("~")),
            .key(.literal("a")), .key(.literal("b")),
            // ESC [ 2 0 1 ~
            .escape, .key(.literal("[")), .key(.literal("2")), .key(.literal("0")),
            .key(.literal("1")), .key(.literal("~")),
        ])
    }

    func testPlanBracketedPasteAppendReturnLandsAfterCloseMarker() {
        let plan = TextProcessing.typingPlan(for: "x", workaround: .bracketedPaste,
                                             stripTrailingNewline: false, appendReturn: true)
        XCTAssertEqual(plan.last, .key(.returnKey))
        // The Return is outside the closing marker (which ends with "~").
        XCTAssertEqual(plan[plan.count - 2], .key(.literal("~")))
    }

    func testPlanOverwriteIndentSelectsLineStartAfterEachReturn() {
        let plan = TextProcessing.typingPlan(for: "a\n  b", workaround: .overwriteIndent,
                                             stripTrailingNewline: false, appendReturn: false)
        XCTAssertEqual(plan, [
            .key(.literal("a")),
            .key(.returnKey), .selectLineStart,
            .key(.literal(" ")), .key(.literal(" ")), .key(.literal("b")),
        ])
    }

    func testPlanOverwriteIndentAppendedReturnHasNoSelectLineStart() {
        // The deliberately appended Return finalizes the paste; selecting back to
        // line start after it would grab text that isn't Peck's to overwrite.
        let plan = TextProcessing.typingPlan(for: "a", workaround: .overwriteIndent,
                                             stripTrailingNewline: false, appendReturn: true)
        XCTAssertEqual(plan, [.key(.literal("a")), .key(.returnKey)])
    }

    func testPlanEmptyContentIsEmpty() {
        XCTAssertTrue(TextProcessing.typingPlan(for: "", workaround: .bracketedPaste,
                                                stripTrailingNewline: false, appendReturn: false).isEmpty)
        // A stripped-to-empty string with no appended Return also yields nothing.
        XCTAssertTrue(TextProcessing.typingPlan(for: "\n", workaround: .bracketedPaste,
                                                stripTrailingNewline: true, appendReturn: false).isEmpty)
    }

    func testPlanRespectsStripTrailingNewline() {
        let plan = TextProcessing.typingPlan(for: "cmd\n", workaround: .none,
                                             stripTrailingNewline: true, appendReturn: false)
        XCTAssertEqual(plan, [.key(.literal("c")), .key(.literal("m")), .key(.literal("d"))])
    }
}
