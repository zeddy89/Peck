import CoreGraphics

/// Pure screen-coordinate conversion, split out from `CoordinateConverter` so it
/// can be unit-tested without a live `NSScreen`.
///
/// AppKit/Cocoa global coordinates use a **bottom-left** origin anchored at the
/// primary display (`NSScreen.screens[0]`). `CGEvent` global coordinates use a
/// **top-left** origin anchored at that same primary display. The two systems
/// share the X axis and the same left edge, so only Y flips:
///
///     CG.y = primaryHeight - Cocoa.y
///
/// This holds for every display position. A display **above** the primary has
/// Cocoa `y > primaryHeight`, which flips to a negative CG y (above the primary's
/// top edge). A display **below** has negative Cocoa y, flipping to CG `y >
/// primaryHeight`. Displays **left/right** carry negative or large-positive X that
/// needs no adjustment because both systems anchor X at the primary's left edge.
enum CoordinateMath {
    static func toCG(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
