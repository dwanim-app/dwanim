import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the pure `SpectrumRenderer.draw` directly: bottom-up bar fill, bar
/// column placement, the palette vertical gradient, level clamping, rect clipping
/// against the base bounds, and the empty-palette fallback — all on synthetic
/// in-memory bitmaps, no graphics framework.
final class SpectrumRendererTests: XCTestCase {

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

    /// True when `(x, y)` still carries the background color (untouched).
    private func isBackground(_ bitmap: DecodedBitmap, x: Int, y: Int) -> Bool {
        let p = pixel(bitmap, x: x, y: y)
        return p.0 == bg.0 && p.1 == bg.1 && p.2 == bg.2 && p.3 == bg.3
    }

    private let bg: (UInt8, UInt8, UInt8, UInt8) = (10, 20, 30, 255)

    /// A small monochrome palette: every entry is the same red, so "is this pixel a
    /// palette color?" reduces to "is it red, not background?" — the gradient
    /// mapping (which entry) is tested separately with a graded palette.
    private let redPalette = [RGBColor(r: 200, g: 0, b: 0)]

    // MARK: - 1. A full level fills the whole bar column

    /// A level of 1.0 fills its bar's full column height: the TOP pixel of the bar
    /// region is a palette color (not background), and so is the bottom.
    func testFullLevelFillsEntireBarColumn() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        // One bar across the whole width; rect is the whole bitmap.
        SpectrumRenderer.draw([1.0], into: &base, x: 0, y: 0, width: 10, height: 10, palette: redPalette)

        // Top pixel of the column is colored (full height reached the top row).
        XCTAssertFalse(isBackground(base, x: 0, y: 0), "top of a full bar should be colored")
        // Bottom pixel is colored too.
        XCTAssertFalse(isBackground(base, x: 0, y: 9), "bottom of a full bar should be colored")
    }

    // MARK: - 2. A zero level leaves the column background

    /// A level of 0.0 leaves that column entirely at the background color.
    func testZeroLevelLeavesColumnBackground() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        SpectrumRenderer.draw([0.0], into: &base, x: 0, y: 0, width: 10, height: 10, palette: redPalette)

        for y in 0..<10 {
            XCTAssertTrue(isBackground(base, x: 0, y: y), "row \(y) of a zero bar should stay background")
        }
    }

    // MARK: - 3. Half level fills the bottom half (bottom-up direction)

    /// A level of 0.5 fills ~half the height: the BOTTOM half is colored and the
    /// TOP half stays background. This verifies bars grow from the bottom UP.
    func testHalfLevelFillsBottomHalfOnly() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        SpectrumRenderer.draw([0.5], into: &base, x: 0, y: 0, width: 10, height: 10, palette: redPalette)

        // Bottom rows colored.
        XCTAssertFalse(isBackground(base, x: 0, y: 9), "bottom row should be colored at level 0.5")
        XCTAssertFalse(isBackground(base, x: 0, y: 6), "lower-middle row should be colored at level 0.5")
        // Top rows untouched.
        XCTAssertTrue(isBackground(base, x: 0, y: 0), "top row should stay background at level 0.5")
        XCTAssertTrue(isBackground(base, x: 0, y: 3), "upper-middle row should stay background at level 0.5")
    }

    // MARK: - 4. Bars land at the expected x columns

    /// Two bars at levels [1.0, 0.0] occupy the LEFT and RIGHT halves: the left
    /// half has a full column and the right half is empty, so bars are laid evenly
    /// across the width at the expected columns.
    func testBarsLandAtExpectedColumns() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        SpectrumRenderer.draw([1.0, 0.0], into: &base, x: 0, y: 0, width: 10, height: 10, palette: redPalette)

        // Left bar's slot (around x=0..4) has a colored column near its center.
        XCTAssertFalse(isBackground(base, x: 1, y: 0), "left bar (level 1.0) should be colored")
        // Right bar's slot (around x=5..9) is empty (level 0.0): bottom row clear.
        XCTAssertTrue(isBackground(base, x: 8, y: 9), "right bar (level 0.0) should stay background")
    }

    // MARK: - 5. Out-of-range levels clamp

    /// Levels above 1.0 clamp to a full bar (no taller than the rect, no trap) and
    /// levels below 0.0 clamp to empty.
    func testOutOfRangeLevelsClamp() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        SpectrumRenderer.draw([5.0, -3.0], into: &base, x: 0, y: 0, width: 10, height: 10, palette: redPalette)

        // The >1 bar fills to the top but no further (buffer length unchanged).
        XCTAssertFalse(isBackground(base, x: 1, y: 0), "clamped-high bar should fill to the top row")
        XCTAssertEqual(base.pixels.count, 10 * 10 * 4, "no out-of-range write grew the buffer")
        // The <0 bar stays empty.
        XCTAssertTrue(isBackground(base, x: 8, y: 9), "clamped-low bar should stay background")
    }

    /// A NaN level must not trap the `Int()` height conversion; it is treated as
    /// silent (that bar's column stays background), while ±inf still clamp.
    func testNaNLevelIsSilentAndDoesNotTrap() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        SpectrumRenderer.draw(
            [Float.nan, .infinity], into: &base, x: 0, y: 0, width: 10, height: 10, palette: redPalette
        )
        // NaN bar (left slot) stays background; +inf bar (right slot) fills full.
        XCTAssertTrue(isBackground(base, x: 1, y: 9), "NaN level should render as silent")
        XCTAssertFalse(isBackground(base, x: 8, y: 0), "+inf level should clamp to a full bar")
        XCTAssertEqual(base.pixels.count, 10 * 10 * 4)
    }

    // MARK: - 6. A rect partly off-bounds clips without crashing

    /// A rect whose right/bottom edges extend past the base is clipped to the base
    /// bounds: full-level bars draw their in-bounds part and the buffer never grows.
    func testRectPartlyOffBoundsClips() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        // Rect starts mid-bitmap and runs off the right and bottom edges.
        SpectrumRenderer.draw(
            [1.0, 1.0, 1.0],
            into: &base, x: 6, y: 6, width: 20, height: 20, palette: redPalette
        )

        // Some in-bounds pixel inside the clipped rect got colored.
        XCTAssertFalse(isBackground(base, x: 7, y: 9), "an in-bounds rect pixel should be colored")
        // Buffer length unchanged (nothing written out of range).
        XCTAssertEqual(base.pixels.count, 10 * 10 * 4)
    }

    /// A rect placed entirely off the base (negative origin past the top-left, or
    /// beyond the right edge) draws nothing and never traps.
    func testRectFullyOffBoundsIsNoOp() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        let original = base

        SpectrumRenderer.draw([1.0], into: &base, x: -50, y: -50, width: 10, height: 10, palette: redPalette)
        SpectrumRenderer.draw([1.0], into: &base, x: 100, y: 100, width: 10, height: 10, palette: redPalette)

        XCTAssertEqual(base, original, "fully off-bounds draws should leave the base untouched")
    }

    /// A size-inconsistent base (buffer shorter than width*height*4) is left
    /// untouched and never traps.
    func testSizeInconsistentBaseIsSkipped() {
        var base = DecodedBitmap(width: 10, height: 10, pixels: [0, 0, 0, 255])
        SpectrumRenderer.draw([1.0], into: &base, x: 0, y: 0, width: 10, height: 10, palette: redPalette)
        XCTAssertEqual(base.pixels, [0, 0, 0, 255])
    }

    // MARK: - 7. Empty palette falls back to a single color (no crash)

    /// An empty palette draws bars in a single fallback color (a sane visible
    /// color, NOT the background) and does not crash.
    func testEmptyPaletteUsesFallbackColor() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        SpectrumRenderer.draw([1.0], into: &base, x: 0, y: 0, width: 10, height: 10, palette: [])

        // The bar is drawn (not background) — a fallback color was used.
        XCTAssertFalse(isBackground(base, x: 1, y: 9), "empty palette should fall back to a visible color")
    }

    // MARK: - 8. The palette is used as a vertical gradient (taller = later entry)

    /// With a two-entry palette [low=blue, high=red], a full bar's BOTTOM pixels map
    /// to the low (blue) entry and its TOP pixels map to the high (red) entry — the
    /// classic "hotter at the top" vertical gradient.
    func testPaletteVerticalGradientMapsHeightToEntry() {
        var base = solidBitmap(width: 10, height: 10, color: bg)
        let lowBlue = RGBColor(r: 0, g: 0, b: 200)
        let highRed = RGBColor(r: 200, g: 0, b: 0)

        SpectrumRenderer.draw(
            [1.0],
            into: &base, x: 0, y: 0, width: 10, height: 10, palette: [lowBlue, highRed]
        )

        // Bottom pixel: low (blue) end of the gradient.
        let bottom = pixel(base, x: 0, y: 9)
        XCTAssertEqual(bottom.2, 200, "bottom of the bar should use the low (blue) palette entry")
        XCTAssertEqual(bottom.0, 0)
        // Top pixel: high (red) end of the gradient.
        let top = pixel(base, x: 0, y: 0)
        XCTAssertEqual(top.0, 200, "top of the bar should use the high (red) palette entry")
        XCTAssertEqual(top.2, 0)
    }

    // MARK: - 9. Filled pixels are opaque

    /// Filled bar pixels are written opaque (alpha 0xFF), matching the opaque-skin
    /// composite contract.
    func testFilledPixelsAreOpaque() {
        var base = solidBitmap(width: 10, height: 10, color: (10, 20, 30, 128))
        SpectrumRenderer.draw([1.0], into: &base, x: 0, y: 0, width: 10, height: 10, palette: redPalette)
        XCTAssertEqual(pixel(base, x: 1, y: 9).3, 255, "filled bar pixels should be opaque")
    }
}
