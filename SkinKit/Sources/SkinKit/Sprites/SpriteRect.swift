import Foundation

// MARK: - SpriteRect

/// A named pixel rectangle within a sprite sheet.
///
/// Coordinates use the same convention as `DecodedBitmap`: the origin is the
/// **top-left** corner, `x` grows rightward and `y` downward, both in whole
/// pixels. The rectangle covers the half-open range `x..<(x + width)` by
/// `y..<(y + height)`.
public struct SpriteRect: Equatable, Sendable {
    /// A stable identifier for the sprite within its sheet (e.g. `"play"`).
    public let name: String
    /// Left edge of the rectangle, in pixels from the sheet's left edge.
    public let x: Int
    /// Top edge of the rectangle, in pixels from the sheet's top edge.
    public let y: Int
    /// Width of the rectangle in pixels.
    public let width: Int
    /// Height of the rectangle in pixels.
    public let height: Int

    public init(name: String, x: Int, y: Int, width: Int, height: Int) {
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
