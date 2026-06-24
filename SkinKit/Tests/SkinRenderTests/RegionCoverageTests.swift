import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the pure polygon→pixel coverage math in `RegionCoverage`: building a
/// row-major visibility mask from a `SkinRegion`'s polygons (scanline fill,
/// top-left origin) and applying that mask to a `DecodedBitmap`'s alpha channel.
/// All synthetic, no graphics framework.
final class RegionCoverageTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a single-polygon `SkinRegion` from `(x, y)` vertex pairs.
    private func region(_ vertices: [(Int, Int)]) -> SkinRegion {
        let points = vertices.map { SkinRegion.Point(x: $0.0, y: $0.1) }
        return SkinRegion(polygons: [SkinRegion.Polygon(points: points)])
    }

    /// Reads the mask cell at `(x, y)` from a row-major `[Bool]` of `width` columns.
    private func at(_ mask: [Bool], x: Int, y: Int, width: Int) -> Bool {
        mask[y * width + x]
    }

    /// A solid-color, fully-opaque RGBA8 bitmap of the given size.
    private func solidBitmap(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8)
    ) -> DecodedBitmap {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = color.0
            pixels[index + 1] = color.1
            pixels[index + 2] = color.2
            pixels[index + 3] = 0xFF
        }
        return DecodedBitmap(width: width, height: height, pixels: pixels)
    }

    /// The RGBA bytes at `(x, y)`, read straight from the buffer. Returned as an
    /// array so it is directly `Equatable` for `XCTAssertEqual`.
    private func pixel(
        _ bitmap: DecodedBitmap,
        x: Int,
        y: Int
    ) -> [UInt8] {
        let index = (y * bitmap.width + x) * 4
        return [
            bitmap.pixels[index],
            bitmap.pixels[index + 1],
            bitmap.pixels[index + 2],
            bitmap.pixels[index + 3]
        ]
    }

    // MARK: - 1. Full rectangle

    /// A polygon covering the whole canvas marks every pixel visible.
    func testFullRectangleMaskAllTrue() {
        let width = 6, height = 5
        let full = region([(0, 0), (width, 0), (width, height), (0, height)])

        let mask = RegionCoverage.mask(full, width: width, height: height)

        XCTAssertEqual(mask.count, width * height)
        XCTAssertTrue(mask.allSatisfy { $0 }, "every pixel should be inside")
    }

    // MARK: - 2. Sub-rectangle

    /// A rectangle covering only part of the canvas: inside pixels true, outside
    /// false, asserted at specific points.
    func testSubRectangleMasksInsideTrueOutsideFalse() {
        let width = 10, height = 10
        // Rectangle from (2,2) to (6,6): covers columns 2..5 and rows 2..5.
        let sub = region([(2, 2), (6, 2), (6, 6), (2, 6)])

        let mask = RegionCoverage.mask(sub, width: width, height: height)

        // Inside (well within the rectangle).
        XCTAssertTrue(at(mask, x: 3, y: 3, width: width))
        XCTAssertTrue(at(mask, x: 5, y: 5, width: width))
        // Outside in every direction.
        XCTAssertFalse(at(mask, x: 0, y: 0, width: width))
        XCTAssertFalse(at(mask, x: 1, y: 3, width: width)) // left of rect
        XCTAssertFalse(at(mask, x: 8, y: 3, width: width)) // right of rect
        XCTAssertFalse(at(mask, x: 3, y: 0, width: width)) // above rect
        XCTAssertFalse(at(mask, x: 3, y: 8, width: width)) // below rect
    }

    // MARK: - 3. Notch / L-shape (concave polygon)

    /// A concave L-shaped polygon: the cut-out notch corner is OUTSIDE, while the
    /// two arms of the L are inside.
    func testLShapeNotchIsOutsideArmsInside() {
        let width = 10, height = 10
        // L-shape: a 8x8 square (1,1)-(9,9) with its top-right quadrant removed,
        // leaving the left arm (full height) and the bottom arm (full width).
        // Vertices walk the outline clockwise:
        //   (1,1) -> (5,1) -> (5,5) -> (9,5) -> (9,9) -> (1,9)
        let lShape = region([
            (1, 1), (5, 1), (5, 5), (9, 5), (9, 9), (1, 9)
        ])

        let mask = RegionCoverage.mask(lShape, width: width, height: height)

        // The notch (removed top-right quadrant) is OUTSIDE.
        XCTAssertFalse(at(mask, x: 7, y: 3, width: width), "notch must be outside")
        // Left arm (column 2, near the top) is inside.
        XCTAssertTrue(at(mask, x: 2, y: 2, width: width), "left arm inside")
        // Bottom arm (right side, near the bottom) is inside.
        XCTAssertTrue(at(mask, x: 7, y: 7, width: width), "bottom arm inside")
    }

    // MARK: - 4. Union of two disjoint polygons

    /// Two separated rectangles: both interiors are inside, the gap between them
    /// is outside (union semantics).
    func testUnionOfTwoDisjointPolygons() {
        let width = 20, height = 8
        let left = SkinRegion.Polygon(points: [
            SkinRegion.Point(x: 1, y: 1),
            SkinRegion.Point(x: 5, y: 1),
            SkinRegion.Point(x: 5, y: 5),
            SkinRegion.Point(x: 1, y: 5)
        ])
        let right = SkinRegion.Polygon(points: [
            SkinRegion.Point(x: 12, y: 1),
            SkinRegion.Point(x: 16, y: 1),
            SkinRegion.Point(x: 16, y: 5),
            SkinRegion.Point(x: 12, y: 5)
        ])
        let twoBoxes = SkinRegion(polygons: [left, right])

        let mask = RegionCoverage.mask(twoBoxes, width: width, height: height)

        // Inside both boxes.
        XCTAssertTrue(at(mask, x: 3, y: 3, width: width), "left box inside")
        XCTAssertTrue(at(mask, x: 14, y: 3, width: width), "right box inside")
        // The gap between them is outside.
        XCTAssertFalse(at(mask, x: 8, y: 3, width: width), "gap outside")
    }

    // MARK: - 5. Empty region

    /// A region with no polygons means "no shape declared" → fully visible.
    func testEmptyRegionAllTrue() {
        let empty = SkinRegion(polygons: [])

        let mask = RegionCoverage.mask(empty, width: 4, height: 3)

        XCTAssertEqual(mask.count, 12)
        XCTAssertTrue(mask.allSatisfy { $0 }, "empty region is fully visible")
    }

    // MARK: - 6. applyMask

    /// A mask that is fully inside leaves every pixel's alpha at 0xFF.
    func testApplyMaskFullyInsideLeavesAlphaOpaque() {
        var bitmap = solidBitmap(width: 4, height: 3, color: (10, 20, 30))
        let mask = [Bool](repeating: true, count: 4 * 3)

        RegionCoverage.applyMask(mask, to: &bitmap)

        for y in 0..<3 {
            for x in 0..<4 {
                XCTAssertEqual(pixel(bitmap, x: x, y: y)[3], 0xFF)
            }
        }
    }

    /// A mask with some false cells zeroes those pixels' alpha (RGB untouched) and
    /// leaves the inside pixels fully intact.
    func testApplyMaskZeroesAlphaOutsideKeepsRGBAndInside() {
        var bitmap = solidBitmap(width: 3, height: 2, color: (11, 22, 33))
        // Mark (0,0) and (2,1) outside, the rest inside.
        var mask = [Bool](repeating: true, count: 3 * 2)
        mask[0 * 3 + 0] = false
        mask[1 * 3 + 2] = false

        RegionCoverage.applyMask(mask, to: &bitmap)

        // Outside pixels: alpha 0, RGB unchanged.
        XCTAssertEqual(pixel(bitmap, x: 0, y: 0), [11, 22, 33, 0])
        XCTAssertEqual(pixel(bitmap, x: 2, y: 1), [11, 22, 33, 0])
        // Inside pixels: fully untouched.
        XCTAssertEqual(pixel(bitmap, x: 1, y: 0), [11, 22, 33, 0xFF])
        XCTAssertEqual(pixel(bitmap, x: 0, y: 1), [11, 22, 33, 0xFF])
    }

    // MARK: - 7. Astronomically large vertex does not crash

    /// A `region.txt` coordinate can be up to `Int.max`. The scanline crossing for
    /// such a vertex is ~`Double(Int.max)`, which is NOT representable as `Int` and
    /// would trap on a naive `Int(...)` conversion. Building a mask from a polygon
    /// with a huge vertex must NOT crash, and must still produce a sane mask: the
    /// span still extends across the visible canvas it covers (clamped), and the
    /// mask stays the right size with valid in-bounds cells.
    func testHugeVertexDoesNotCrashAndProducesSaneMask() {
        let width = 10, height = 10
        // A triangle whose right vertex sits astronomically far off-canvas at
        // x = Int.max. Its left edge stays on-canvas; rows it spans should still
        // mark columns from the left edge rightward, clamped to the canvas width.
        let huge = region([
            (1, 1),
            (Int.max, 5),
            (1, 9)
        ])

        // Must not trap on the out-of-Int-range crossing.
        let mask = RegionCoverage.mask(huge, width: width, height: height)

        // Size is correct and no spurious out-of-canvas marking occurred.
        XCTAssertEqual(mask.count, width * height)
        // A point near the left vertex (inside the triangle) is visible, proving
        // the huge-vertex edge was clamped rather than skipped or trapped.
        XCTAssertTrue(at(mask, x: 2, y: 5, width: width), "near-left interior inside")
        // The clamp keeps marking within the canvas: the rightmost column on the
        // mid row is marked (the span was clamped to width-1, not dropped).
        XCTAssertTrue(at(mask, x: width - 1, y: 5, width: width), "clamped to canvas edge")
    }

    // MARK: - 8. applyMask

    /// A size-mismatched mask leaves the bitmap completely unchanged.
    func testApplyMaskSizeMismatchLeavesBitmapUnchanged() {
        let original = solidBitmap(width: 4, height: 3, color: (1, 2, 3))
        var bitmap = original
        // Wrong length (should be 12).
        let mask = [Bool](repeating: false, count: 5)

        RegionCoverage.applyMask(mask, to: &bitmap)

        XCTAssertEqual(bitmap, original, "mismatched mask must not alter the bitmap")
    }
}
