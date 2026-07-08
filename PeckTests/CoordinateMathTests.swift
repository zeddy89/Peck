import XCTest
import CoreGraphics

// Note: Peck ships as a menu-bar agent app whose launch installs a status item and
// prompts for Accessibility. To keep `xcodebuild test` headless and side-effect-free,
// this is a host-less logic-test bundle: the pure source files under test are compiled
// directly into the test target (see project.pbxproj), so there is no `import Peck`.

/// Verifies the Cocoa (bottom-left, primary-anchored) → CGEvent (top-left,
/// primary-anchored) Y-flip for displays in every position relative to primary.
final class CoordinateMathTests: XCTestCase {

    private let primaryHeight: CGFloat = 1080

    private func cg(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CoordinateMath.toCG(CGPoint(x: x, y: y), primaryHeight: primaryHeight)
    }

    func testOnPrimaryDisplay() {
        // A point 900pt up from primary's bottom edge is 180pt down from its top.
        XCTAssertEqual(cg(100, 900), CGPoint(x: 100, y: 180))
    }

    func testPrimaryCorners() {
        // Bottom-left of primary (Cocoa origin) maps to bottom-left in CG space.
        XCTAssertEqual(cg(0, 0), CGPoint(x: 0, y: 1080))
        // Top-left of primary maps to the CG origin.
        XCTAssertEqual(cg(0, 1080), CGPoint(x: 0, y: 0))
    }

    func testDisplayToTheRight() {
        // X is shared between both coordinate systems; only Y flips.
        XCTAssertEqual(cg(2000, 900), CGPoint(x: 2000, y: 180))
    }

    func testDisplayToTheLeft() {
        // A display left of primary carries negative Cocoa X, preserved verbatim.
        XCTAssertEqual(cg(-500, 900), CGPoint(x: -500, y: 180))
    }

    func testDisplayAbovePrimary() {
        // Above primary: Cocoa y > primaryHeight → negative CG y (above the top edge).
        XCTAssertEqual(cg(100, 1500), CGPoint(x: 100, y: -420))
    }

    func testDisplayBelowPrimary() {
        // Below primary: negative Cocoa y → CG y greater than primaryHeight.
        XCTAssertEqual(cg(100, -300), CGPoint(x: 100, y: 1380))
    }

    func testRoundTripIsInvolutive() {
        // Flipping twice against the same height returns the original point.
        let start = CGPoint(x: 640, y: 512)
        let there = CoordinateMath.toCG(start, primaryHeight: primaryHeight)
        let back = CoordinateMath.toCG(there, primaryHeight: primaryHeight)
        XCTAssertEqual(back, start)
    }
}
