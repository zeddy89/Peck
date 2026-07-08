import XCTest
import CoreGraphics

/// Exercises the layout-aware character → keycode table on the *current* keyboard
/// layout. These skip gracefully where no Unicode keyboard layout is resolvable
/// (headless CI, exotic input sources) rather than failing.
final class KeyMapperTests: XCTestCase {

    private func makeMapper() throws -> KeyMapper {
        try XCTUnwrap(KeyMapper(), "No resolvable Unicode keyboard layout on this host")
    }

    func testLowercaseLettersMapWithoutShift() throws {
        let mapper = try makeMapper()
        for scalar in UnicodeScalar("a").value...UnicodeScalar("z").value {
            let ch = Character(UnicodeScalar(scalar)!)
            let stroke = try XCTUnwrap(mapper.stroke(for: ch), "no stroke for \(ch)")
            XCTAssertFalse(stroke.flags.contains(.maskShift), "\(ch) should be unshifted")
        }
    }

    func testUppercaseLettersCarryShiftAndShareKeycodeWithLowercase() throws {
        let mapper = try makeMapper()
        for scalar in UnicodeScalar("a").value...UnicodeScalar("z").value {
            let lower = Character(UnicodeScalar(scalar)!)
            let upper = Character(UnicodeScalar(scalar - 32)!) // 'a'-32 == 'A'
            let lowerStroke = try XCTUnwrap(mapper.stroke(for: lower))
            let upperStroke = try XCTUnwrap(mapper.stroke(for: upper))
            XCTAssertTrue(upperStroke.flags.contains(.maskShift), "\(upper) should require Shift")
            // Same physical key, differing only by the Shift modifier.
            XCTAssertEqual(lowerStroke.keyCode, upperStroke.keyCode, "\(lower)/\(upper) should share a keycode")
        }
    }

    func testDigitsMap() throws {
        let mapper = try makeMapper()
        for scalar in UnicodeScalar("0").value...UnicodeScalar("9").value {
            let ch = Character(UnicodeScalar(scalar)!)
            XCTAssertNotNil(mapper.stroke(for: ch), "no stroke for digit \(ch)")
        }
    }

    func testSpaceMaps() throws {
        let mapper = try makeMapper()
        XCTAssertNotNil(mapper.stroke(for: " "))
    }

    func testPrintableAsciiCoverageIsHigh() throws {
        let mapper = try makeMapper()
        var mapped = 0
        var total = 0
        for scalar in UInt32(0x20)...UInt32(0x7E) {
            total += 1
            if mapper.stroke(for: Character(UnicodeScalar(scalar)!)) != nil { mapped += 1 }
        }
        // Every Latin layout can produce letters, digits, space and common
        // punctuation. Allow a small margin for layout-specific dead keys.
        XCTAssertGreaterThanOrEqual(Double(mapped) / Double(total), 0.9,
                                    "only \(mapped)/\(total) printable ASCII chars mapped")
    }

    func testControlCharactersAreNotMapped() throws {
        let mapper = try makeMapper()
        // The builder filters out control chars (< 0x20) and DEL (0x7F).
        XCTAssertNil(mapper.stroke(for: "\u{01}"))
        XCTAssertNil(mapper.stroke(for: "\u{7F}"))
    }
}
