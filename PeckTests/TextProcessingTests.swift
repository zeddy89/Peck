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

    // MARK: - TextNormalizer

    func testNormalizedLineBreaks() {
        XCTAssertEqual(TextNormalizer.normalizedLineBreaks("a\r\nb\rc\u{2028}d"), "a\nb\nc\nd")
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
}
