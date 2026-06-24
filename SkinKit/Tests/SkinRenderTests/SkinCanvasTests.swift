import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the promoted blit primitive `SkinCanvas.overlay` directly: the
/// opaque-overwrite placement, edge clipping, and the size-inconsistency skip
/// guards — all on synthetic in-memory bitmaps, no graphics framework.
final class SkinCanvasTests: XCTestCase {

    // MARK: - Helpers

    /// A solid-color RGBA8 bitmap of the given size, every pixel set to `color`.
    private func solidBitmap(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8, UInt8)
    ) -> DecodedBitmap {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = color.0
            pixels[index + 1] = color.1
            pixels[index + 2] = color.2
            pixels[index + 3] = color.3
        }
        return DecodedBitmap(width: width, height: height, pixels: pixels)
    }

    /// The RGBA tuple at `(x, y)` in a bitmap, read straight from the buffer.
    private func pixel(_ bitmap: DecodedBitmap, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * bitmap.width + x) * 4
        return (
            bitmap.pixels[index],
            bitmap.pixels[index + 1],
            bitmap.pixels[index + 2],
            bitmap.pixels[index + 3]
        )
    }

    private let bgColor: (UInt8, UInt8, UInt8, UInt8) = (10, 20, 30, 255)
    private let fgColor: (UInt8, UInt8, UInt8, UInt8) = (200, 100, 50, 255)

    // MARK: - 1. Placement

    /// A sprite overlaid at (x, y) lands with its top-left at (x, y), opaquely
    /// overwriting the base, and leaves uncovered pixels at the base color.
    func testOverlayPlacesSpriteAtOriginWithOpaqueOverwrite() {
        var base = solidBitmap(width: 20, height: 20, color: bgColor)
        let sprite = solidBitmap(width: 4, height: 4, color: fgColor)

        SkinCanvas.overlay(sprite, onto: &base, x: 5, y: 6)

        // Covered: every pixel of the 4x4 footprint equals the sprite color.
        XCTAssertEqual(pixel(base, x: 5, y: 6).0, fgColor.0)
        XCTAssertEqual(pixel(base, x: 8, y: 9).0, fgColor.0)
        XCTAssertEqual(pixel(base, x: 8, y: 9).1, fgColor.1)
        // Just outside the footprint stays background.
        XCTAssertEqual(pixel(base, x: 4, y: 6).0, bgColor.0)
        XCTAssertEqual(pixel(base, x: 9, y: 9).0, bgColor.0)
    }

    // MARK: - 2. Clipping

    /// A sprite that extends past the right/bottom edges has only its in-bounds
    /// part copied; nothing is written out of range.
    func testOverlayClipsAtRightAndBottomEdges() {
        var base = solidBitmap(width: 10, height: 10, color: bgColor)
        let sprite = solidBitmap(width: 6, height: 6, color: fgColor)

        SkinCanvas.overlay(sprite, onto: &base, x: 7, y: 7)

        // In-bounds 3x3 part copied.
        XCTAssertEqual(pixel(base, x: 7, y: 7).0, fgColor.0)
        XCTAssertEqual(pixel(base, x: 9, y: 9).0, fgColor.0)
        // Just outside the sprite footprint stays background.
        XCTAssertEqual(pixel(base, x: 6, y: 6).0, bgColor.0)
        // Buffer length is unchanged (no out-of-range write grew it).
        XCTAssertEqual(base.pixels.count, 10 * 10 * 4)
    }

    /// A sprite placed at a negative origin clips its top-left off the base.
    func testOverlayClipsAtTopLeftWithNegativeOrigin() {
        var base = solidBitmap(width: 10, height: 10, color: bgColor)
        let sprite = solidBitmap(width: 6, height: 6, color: fgColor)

        SkinCanvas.overlay(sprite, onto: &base, x: -3, y: -3)

        // Only the bottom-right 3x3 of the sprite is in bounds, landing at (0,0).
        XCTAssertEqual(pixel(base, x: 0, y: 0).0, fgColor.0)
        XCTAssertEqual(pixel(base, x: 2, y: 2).0, fgColor.0)
        // Beyond that footprint stays background.
        XCTAssertEqual(pixel(base, x: 3, y: 3).0, bgColor.0)
    }

    // MARK: - 3. Size-inconsistency skip

    /// A sprite whose buffer is shorter than its declared dimensions is skipped
    /// silently; the base is untouched and nothing traps.
    func testOverlaySkipsSizeInconsistentSprite() {
        var base = solidBitmap(width: 10, height: 10, color: bgColor)
        // Declares 6x6 (864 bytes) but only carries 4.
        let malformed = DecodedBitmap(width: 6, height: 6, pixels: [0, 0, 0, 255])

        SkinCanvas.overlay(malformed, onto: &base, x: 0, y: 0)

        XCTAssertEqual(pixel(base, x: 0, y: 0).0, bgColor.0)
        XCTAssertEqual(base.pixels.count, 10 * 10 * 4)
    }

    /// A base whose buffer is shorter than its declared dimensions is left
    /// untouched (the overlay is skipped silently), never trapping.
    func testOverlaySkipsSizeInconsistentBase() {
        // Declares 10x10 but only carries 4 bytes.
        var base = DecodedBitmap(width: 10, height: 10, pixels: [0, 0, 0, 255])
        let sprite = solidBitmap(width: 4, height: 4, color: fgColor)

        SkinCanvas.overlay(sprite, onto: &base, x: 0, y: 0)

        // Untouched: still the original 4-byte buffer.
        XCTAssertEqual(base.pixels, [0, 0, 0, 255])
    }
}
