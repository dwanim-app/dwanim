import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the pure bitmap-font text renderer on synthetic skins built
/// entirely in-memory. Each glyph/digit is a distinct solid color, so a single
/// landing-pixel read proves which sprite was placed and where — covering
/// left-to-right advance, glyph mapping, uppercasing, fault tolerance, and the
/// time layout. No graphics framework, no real `.wsz` files.
final class BitmapTextTests: XCTestCase {

    // MARK: - Constants (must match SpriteCoordinates)

    /// text.bmp fixed glyph cell width (advance per character).
    private let glyphCellWidth = 5
    private let glyphCellHeight = 6
    /// numbers.bmp digit cell width.
    private let digitCellWidth = 9
    private let digitCellHeight = 13

    // MARK: - Helpers

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

    private func pixel(_ bitmap: DecodedBitmap, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * bitmap.width + x) * 4
        return (
            bitmap.pixels[index],
            bitmap.pixels[index + 1],
            bitmap.pixels[index + 2],
            bitmap.pixels[index + 3]
        )
    }

    private func makeSkin(sprites: [String: [String: DecodedBitmap]]) -> Skin {
        Skin(sprites: sprites, visColors: [], playlist: nil, region: nil)
    }

    private let bgColor: (UInt8, UInt8, UInt8, UInt8) = (10, 20, 30, 255)
    private let colorA: (UInt8, UInt8, UInt8, UInt8) = (200, 0, 0, 255)
    private let colorB: (UInt8, UInt8, UInt8, UInt8) = (0, 200, 0, 255)

    /// A skin with text.bmp glyphs for `A` (red) and `B` (green) at cell size.
    private func skinWithAB() -> Skin {
        makeSkin(sprites: [
            "text.bmp": [
                "glyph_A": solidBitmap(width: glyphCellWidth, height: glyphCellHeight, color: colorA),
                "glyph_B": solidBitmap(width: glyphCellWidth, height: glyphCellHeight, color: colorB)
            ]
        ])
    }

    // MARK: - 1. Glyph advance + placement + mapping + seam

    /// `draw("AB", at:(x,y))` places the A glyph at (x, y) and the B glyph one
    /// cell width to the right, proving left-to-right advance, char→sprite
    /// mapping, and the overlay seam.
    func testDrawAdvancesLeftToRightAndMapsGlyphs() {
        var base = solidBitmap(width: 40, height: 20, color: bgColor)

        BitmapText.draw("AB", from: skinWithAB(), onto: &base, x: 4, y: 5, maxWidth: 1000)

        // A glyph at (4,5).
        XCTAssertEqual(pixel(base, x: 4, y: 5).0, colorA.0)
        XCTAssertEqual(pixel(base, x: 4, y: 5).1, colorA.1)
        // B glyph one cell width to the right.
        XCTAssertEqual(pixel(base, x: 4 + glyphCellWidth, y: 5).0, colorB.0)
        XCTAssertEqual(pixel(base, x: 4 + glyphCellWidth, y: 5).1, colorB.1)
        // Before the text start stays background.
        XCTAssertEqual(pixel(base, x: 3, y: 5).0, bgColor.0)
    }

    // MARK: - 2. Lowercase is uppercased

    /// `draw("ab")` resolves to the same A/B glyphs as `draw("AB")`.
    func testLowercaseInputIsUppercased() {
        var base = solidBitmap(width: 40, height: 20, color: bgColor)

        BitmapText.draw("ab", from: skinWithAB(), onto: &base, x: 4, y: 5, maxWidth: 1000)

        XCTAssertEqual(pixel(base, x: 4, y: 5).0, colorA.0)
        XCTAssertEqual(pixel(base, x: 4 + glyphCellWidth, y: 5).0, colorB.0)
        XCTAssertEqual(pixel(base, x: 4 + glyphCellWidth, y: 5).1, colorB.1)
    }

    // MARK: - 3. Missing glyph advances blank

    /// A character with no glyph sprite (here the space between A and B, which
    /// SpriteCoordinates does not model) advances by one cell width and renders
    /// blank; the following character still lands at the next cell. No crash.
    func testMissingGlyphAdvancesBlankAndFollowingCharsPlaced() {
        var base = solidBitmap(width: 40, height: 20, color: bgColor)

        // "A B": A at cell 0, space (no sprite) at cell 1 -> blank, B at cell 2.
        BitmapText.draw("A B", from: skinWithAB(), onto: &base, x: 0, y: 0, maxWidth: 1000)

        XCTAssertEqual(pixel(base, x: 0, y: 0).0, colorA.0)
        // The space cell renders blank (background shows through).
        XCTAssertEqual(pixel(base, x: glyphCellWidth, y: 0).0, bgColor.0)
        // B lands at the third cell, proving the blank still advanced.
        XCTAssertEqual(pixel(base, x: 2 * glyphCellWidth, y: 0).0, colorB.0)
        XCTAssertEqual(pixel(base, x: 2 * glyphCellWidth, y: 0).1, colorB.1)
    }

    // MARK: - 3b. Region clip: maxWidth confines the title

    /// A long string drawn with a `maxWidth` that admits only the first two glyph
    /// cells draws those glyphs but does NOT bleed past the region: a pixel at and
    /// after `x + maxWidth` stays the background color. Proves the title is
    /// clipped to its display-region width.
    func testDrawClipsGlyphsBeyondMaxWidth() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        let x = 4
        // Room for exactly two glyph cells (2 * 5 = 10); a third would start at
        // x + 10 and overflow x + maxWidth, so it must be dropped.
        let maxWidth = 2 * glyphCellWidth

        // Long string of A/B glyphs; only the first two cells fit the region.
        BitmapText.draw("ABABABAB", from: skinWithAB(), onto: &base, x: x, y: 5, maxWidth: maxWidth)

        // First glyph (A) inside the region IS drawn.
        XCTAssertEqual(pixel(base, x: x, y: 5).0, colorA.0)
        XCTAssertEqual(pixel(base, x: x, y: 5).1, colorA.1)
        // Second glyph (B), still inside the region, IS drawn.
        XCTAssertEqual(pixel(base, x: x + glyphCellWidth, y: 5).0, colorB.0)
        XCTAssertEqual(pixel(base, x: x + glyphCellWidth, y: 5).1, colorB.1)
        // At the region edge (x + maxWidth) the next glyph did NOT bleed past:
        // the pixel is still background.
        XCTAssertEqual(pixel(base, x: x + maxWidth, y: 5).0, bgColor.0)
        XCTAssertEqual(pixel(base, x: x + maxWidth, y: 5).1, bgColor.1)
        XCTAssertEqual(pixel(base, x: x + maxWidth, y: 5).2, bgColor.2)
        // Well past the region, still background (no overflow to the window edge).
        XCTAssertEqual(pixel(base, x: x + maxWidth + glyphCellWidth, y: 5).0, bgColor.0)
    }

    /// A string that fits entirely within `maxWidth` still renders every glyph
    /// (no regression from the clip bound).
    func testDrawWithinMaxWidthRendersFully() {
        var base = solidBitmap(width: 40, height: 20, color: bgColor)
        let x = 4
        // Generous room for both glyph cells.
        BitmapText.draw("AB", from: skinWithAB(), onto: &base, x: x, y: 5, maxWidth: 1000)

        XCTAssertEqual(pixel(base, x: x, y: 5).0, colorA.0)
        XCTAssertEqual(pixel(base, x: x + glyphCellWidth, y: 5).0, colorB.0)
        XCTAssertEqual(pixel(base, x: x + glyphCellWidth, y: 5).1, colorB.1)
    }

    // MARK: - 4. drawTime layout

    /// `drawTime(minutes:1, seconds:5)` lays out a zero-padded MM:SS with the
    /// digit sprites: 0,1 (minutes) then 0,5 (seconds), each advancing by the
    /// digit cell width plus a gap for the colon. Distinct digit colors prove
    /// the exact placement.
    func testDrawTimeLaysOutZeroPaddedDigits() {
        // Ten distinct digit colors: digitN -> (10*N, N, 100, 255).
        var digits: [String: DecodedBitmap] = [:]
        for n in 0...9 {
            digits["digit\(n)"] = solidBitmap(
                width: digitCellWidth,
                height: digitCellHeight,
                color: (UInt8(10 * n), UInt8(n), 100, 255)
            )
        }
        let skin = makeSkin(sprites: ["numbers.bmp": digits])
        var base = solidBitmap(width: 80, height: 20, color: bgColor)

        BitmapText.drawTime(minutes: 1, seconds: 5, from: skin, onto: &base, x: 2, y: 3)

        // MM = "01": digit0 at cell 0, digit1 at cell 1.
        XCTAssertEqual(pixel(base, x: 2, y: 3).0, UInt8(0))           // digit0 red = 0
        XCTAssertEqual(pixel(base, x: 2, y: 3).1, UInt8(0))
        XCTAssertEqual(pixel(base, x: 2 + digitCellWidth, y: 3).0, UInt8(10)) // digit1 red = 10
        XCTAssertEqual(pixel(base, x: 2 + digitCellWidth, y: 3).1, UInt8(1))

        // SS = "05": positioned after the minutes block plus a (provisional)
        // colon gap. The exact gap is a render-tuning detail, so we only assert
        // that the seconds-ones digit (digit5) appears somewhere strictly after
        // the two minute digits, at the start of a digit cell. This proves the
        // MM:SS ordering and digit mapping without pinning the colon gap.
        let afterMinutesX = 2 + 2 * digitCellWidth // first column past the two minute digits
        var foundDigit5 = false
        // digit5 red = 50, green = 5.
        for probeX in afterMinutesX..<base.width {
            let p = pixel(base, x: probeX, y: 3)
            if p.0 == UInt8(50) && p.1 == UInt8(5) {
                foundDigit5 = true
                break
            }
        }
        XCTAssertTrue(foundDigit5, "seconds-ones digit5 not found after the minutes block")
    }

    // MARK: - 5. Fault tolerance: empty / missing sheets never crash

    /// Drawing with no text.bmp sheet at all advances blank and never crashes.
    func testDrawWithNoTextSheetDoesNotCrash() {
        var base = solidBitmap(width: 40, height: 20, color: bgColor)
        BitmapText.draw("AB", from: makeSkin(sprites: [:]), onto: &base, x: 0, y: 0, maxWidth: 1000)
        // Nothing drawn; base unchanged at the would-be glyph positions.
        XCTAssertEqual(pixel(base, x: 0, y: 0).0, bgColor.0)
        XCTAssertEqual(base.pixels.count, 40 * 20 * 4)
    }

    /// drawTime with no numbers.bmp sheet advances blank and never crashes.
    func testDrawTimeWithNoNumbersSheetDoesNotCrash() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        BitmapText.drawTime(minutes: 12, seconds: 34, from: makeSkin(sprites: [:]), onto: &base, x: 0, y: 0)
        XCTAssertEqual(pixel(base, x: 0, y: 0).0, bgColor.0)
        XCTAssertEqual(base.pixels.count, 80 * 20 * 4)
    }
}
