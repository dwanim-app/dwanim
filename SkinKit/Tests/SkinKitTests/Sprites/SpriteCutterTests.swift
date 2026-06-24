import Foundation
import XCTest
@testable import SkinKit

/// Tests for the pure sprite-cutting engine. The engine copies sub-rectangles
/// out of an RGBA8 sheet (top-left origin, row stride `width * 4`) into their
/// own `DecodedBitmap`s. These tests use synthetic sheets only — no real skin
/// files — so they pin down origin, stride, edge handling, and fault tolerance.
final class SpriteCutterTests: XCTestCase {

    // MARK: - Synthetic sheet helper

    /// Builds a sheet whose every channel encodes the pixel's own coordinates so
    /// any transpose, stride, or offset mistake produces a detectable mismatch:
    /// R = x, G = y, B = x ^ y, A = 255 (all modulo 256).
    private func patternedSheet(width: Int, height: Int) -> DecodedBitmap {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i + 0] = UInt8(x & 0xFF)
                pixels[i + 1] = UInt8(y & 0xFF)
                pixels[i + 2] = UInt8((x ^ y) & 0xFF)
                pixels[i + 3] = 255
            }
        }
        return DecodedBitmap(width: width, height: height, pixels: pixels)
    }

    /// Returns the expected RGBA bytes a sprite cut at (`originX`, `originY`)
    /// from a patterned sheet should contain, computed independently from the
    /// engine so the assertion does not echo the implementation.
    private func expectedPatternPixels(originX: Int, originY: Int, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let sx = originX + x
                let sy = originY + y
                pixels[i + 0] = UInt8(sx & 0xFF)
                pixels[i + 1] = UInt8(sy & 0xFF)
                pixels[i + 2] = UInt8((sx ^ sy) & 0xFF)
                pixels[i + 3] = 255
            }
        }
        return pixels
    }

    // MARK: - Criterion 1: exact dimensions, correct pixels, no transpose

    func testCutCopiesExactSubRectanglesAtKnownOffsets() {
        let sheet = patternedSheet(width: 16, height: 12)
        let rects = [
            SpriteRect(name: "a", x: 0, y: 0, width: 4, height: 3),
            SpriteRect(name: "b", x: 5, y: 4, width: 6, height: 2)
        ]

        let result = SpriteCutter.cut(sheet, rects: rects)

        XCTAssertEqual(result.count, 2)

        let a = result["a"]
        XCTAssertEqual(a?.width, 4)
        XCTAssertEqual(a?.height, 3)
        XCTAssertEqual(a?.pixels, expectedPatternPixels(originX: 0, originY: 0, width: 4, height: 3))

        let b = result["b"]
        XCTAssertEqual(b?.width, 6)
        XCTAssertEqual(b?.height, 2)
        XCTAssertEqual(b?.pixels, expectedPatternPixels(originX: 5, originY: 4, width: 6, height: 2))
    }

    func testCutDoesNotTransposeNonSquareRect() {
        // A 1-pixel-wide tall strip would survive a transpose bug with equal
        // dimensions; a 5x2 rect would not. Verify the strip lands as 2x5.
        let sheet = patternedSheet(width: 8, height: 8)
        let result = SpriteCutter.cut(sheet, rects: [SpriteRect(name: "strip", x: 3, y: 1, width: 2, height: 5)])

        let strip = result["strip"]
        XCTAssertEqual(strip?.width, 2)
        XCTAssertEqual(strip?.height, 5)
        XCTAssertEqual(strip?.pixels, expectedPatternPixels(originX: 3, originY: 1, width: 2, height: 5))
    }

    // MARK: - Criterion 2: out-of-bounds rects are skipped, in-bounds still succeed

    func testRectExtendingPastRightOrBottomEdgeIsSkipped() {
        let sheet = patternedSheet(width: 10, height: 10)
        let rects = [
            SpriteRect(name: "tooWide", x: 6, y: 0, width: 5, height: 2),   // 6+5 = 11 > 10
            SpriteRect(name: "tooTall", x: 0, y: 8, width: 2, height: 5),   // 8+5 = 13 > 10
            SpriteRect(name: "ok", x: 0, y: 0, width: 3, height: 3)
        ]

        let result = SpriteCutter.cut(sheet, rects: rects)

        XCTAssertNil(result["tooWide"])
        XCTAssertNil(result["tooTall"])
        XCTAssertNotNil(result["ok"])
        XCTAssertEqual(result.count, 1)
    }

    func testRectWithNegativeOriginIsSkipped() {
        let sheet = patternedSheet(width: 10, height: 10)
        let rects = [
            SpriteRect(name: "negX", x: -1, y: 0, width: 2, height: 2),
            SpriteRect(name: "negY", x: 0, y: -1, width: 2, height: 2),
            SpriteRect(name: "ok", x: 1, y: 1, width: 2, height: 2)
        ]

        let result = SpriteCutter.cut(sheet, rects: rects)

        XCTAssertNil(result["negX"])
        XCTAssertNil(result["negY"])
        XCTAssertNotNil(result["ok"])
    }

    func testRectFullyOutsideSheetIsSkipped() {
        let sheet = patternedSheet(width: 4, height: 4)
        let result = SpriteCutter.cut(sheet, rects: [SpriteRect(name: "far", x: 100, y: 100, width: 1, height: 1)])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Criterion 3: rects touching the right/bottom edge exactly are cut

    func testRectTouchingRightAndBottomEdgeIsCut() {
        let sheet = patternedSheet(width: 10, height: 10)
        // 7+3 = 10 == width, 6+4 = 10 == height: exactly flush, must be kept.
        let rect = SpriteRect(name: "corner", x: 7, y: 6, width: 3, height: 4)

        let result = SpriteCutter.cut(sheet, rects: [rect])

        let corner = result["corner"]
        XCTAssertEqual(corner?.width, 3)
        XCTAssertEqual(corner?.height, 4)
        XCTAssertEqual(corner?.pixels, expectedPatternPixels(originX: 7, originY: 6, width: 3, height: 4))
    }

    func testRectCoveringWholeSheetIsCut() {
        let sheet = patternedSheet(width: 5, height: 5)
        let result = SpriteCutter.cut(sheet, rects: [SpriteRect(name: "all", x: 0, y: 0, width: 5, height: 5)])

        XCTAssertEqual(result["all"], sheet)
    }

    // MARK: - Criterion 4: empty inputs handled without crash

    func testEmptyRectListReturnsEmptyResult() {
        let sheet = patternedSheet(width: 8, height: 8)
        XCTAssertTrue(SpriteCutter.cut(sheet, rects: []).isEmpty)
    }

    func testZeroSizeSheetSkipsAllRectsWithoutCrash() {
        let sheet = DecodedBitmap(width: 0, height: 0, pixels: [])
        let result = SpriteCutter.cut(sheet, rects: [SpriteRect(name: "x", x: 0, y: 0, width: 1, height: 1)])
        XCTAssertTrue(result.isEmpty)
    }

    func testZeroSizeRectIsSkipped() {
        let sheet = patternedSheet(width: 4, height: 4)
        let result = SpriteCutter.cut(sheet, rects: [
            SpriteRect(name: "zeroW", x: 0, y: 0, width: 0, height: 2),
            SpriteRect(name: "zeroH", x: 0, y: 0, width: 2, height: 0)
        ])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Criterion 5: undersized backing buffer is skipped, never traps

    func testUndersizedSheetBufferSkipsRectsWithoutCrash() {
        // `DecodedBitmap` does not enforce that `pixels.count == width*height*4`,
        // so a sheet can claim to be 4x4 (64 bytes) while holding far fewer. An
        // in-bounds rect must be skipped rather than reading past the buffer and
        // trapping; if the guard were missing, this process would abort here.
        let undersized = DecodedBitmap(width: 4, height: 4, pixels: [0, 0, 0, 0])
        let result = SpriteCutter.cut(undersized, rects: [SpriteRect(name: "x", x: 0, y: 0, width: 2, height: 2)])
        XCTAssertEqual(result, [:])
    }
}
