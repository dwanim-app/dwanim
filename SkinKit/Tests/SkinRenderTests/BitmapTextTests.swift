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

    // MARK: - 6. Scrolling marquee
    //
    // The scrolling entry renders the title shifted left by an `offset`, with a
    // fixed separator gap appended so it loops seamlessly, PIXEL-clipped to the
    // window `[x, x + maxWidth)`. These tests use full-cell solid glyphs so that
    // every column of a cell carries the glyph color — that makes the per-pixel
    // clip boundaries crisp and directly assertable.

    /// `pixelWidth` mirrors how `draw()` advances: one glyph cell per character,
    /// whether or not a glyph exists. So "AB" is two cells wide.
    func testPixelWidthMatchesPerCharacterAdvance() {
        XCTAssertEqual(BitmapText.pixelWidth(of: "AB"), 2 * glyphCellWidth)
        XCTAssertEqual(BitmapText.pixelWidth(of: "A B"), 3 * glyphCellWidth) // space counts
        XCTAssertEqual(BitmapText.pixelWidth(of: ""), 0)
    }

    /// The scroll cycle is the text width plus a fixed, non-zero separator gap; it
    /// is strictly wider than the text alone (the separator is what makes the loop
    /// read as a gap rather than the title abutting itself).
    func testScrollCycleWidthIsTextPlusNonZeroSeparator() {
        let textWidth = BitmapText.pixelWidth(of: "AB")
        let cycle = BitmapText.scrollCycleWidth(of: "AB")
        XCTAssertGreaterThan(cycle, textWidth)
    }

    /// At offset 0 with a long title, the first glyph lands at `x`; content that
    /// would fall past the right edge is NOT drawn; and — crucially — no pixel is
    /// ever written at a column `< x` or `>= x + maxWidth`. We prove the latter by
    /// pre-filling the whole base with background and asserting the columns just
    /// outside the window on both sides stay untouched.
    func testScrollingOffsetZeroClipsToWindowAndNeverWritesOutside() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        let x = 10
        let maxWidth = 3 * glyphCellWidth // room for exactly three cells
        let y = 5

        // Long run of full-cell A glyphs.
        BitmapText.drawScrolling(
            "AAAAAAAA", from: skinWithAB(), onto: &base, x: x, y: y, maxWidth: maxWidth, offset: 0
        )

        // First glyph column lands exactly at the window's left edge.
        XCTAssertEqual(pixel(base, x: x, y: y).0, colorA.0)
        // Inside the window: still glyph color.
        XCTAssertEqual(pixel(base, x: x + maxWidth - 1, y: y).0, colorA.0)
        // The column just LEFT of the window was never written.
        XCTAssertEqual(pixel(base, x: x - 1, y: y).0, bgColor.0)
        // The column at the right edge (x + maxWidth) is OUTSIDE -> untouched.
        XCTAssertEqual(pixel(base, x: x + maxWidth, y: y).0, bgColor.0)
        // Well past the right edge: still background (no bleed to the buffer edge).
        XCTAssertEqual(pixel(base, x: x + maxWidth + 2, y: y).0, bgColor.0)
    }

    /// Increasing the offset by one pixel shifts the rendered content one pixel to
    /// the left: a glyph boundary visible at column `c` for offset `O` appears at
    /// `c - 1` for offset `O + 1`. We detect the A→(gap) boundary using a title
    /// whose glyph then runs out, so there is a color transition to track.
    func testIncreasingOffsetShiftsContentLeftByOnePixel() {
        let x = 10
        let maxWidth = 6 * glyphCellWidth
        let y = 5

        // Two A cells then the rest blank (no glyph), giving a clear A→bg edge
        // inside the window that we can locate and watch move left.
        let title = "AAXXXXXXXX" // X has no glyph in skinWithAB -> blank cells
        func firstBackgroundColumn(offset: Int) -> Int? {
            var base = solidBitmap(width: 100, height: 20, color: bgColor)
            BitmapText.drawScrolling(
                title, from: skinWithAB(), onto: &base, x: x, y: y, maxWidth: maxWidth, offset: offset
            )
            for col in x..<(x + maxWidth) where pixel(base, x: col, y: y).0 == bgColor.0 {
                return col
            }
            return nil
        }

        guard let edge0 = firstBackgroundColumn(offset: 0),
              let edge1 = firstBackgroundColumn(offset: 1) else {
            return XCTFail("expected an A→background edge inside the window at both offsets")
        }
        // One more pixel scrolled off the left -> the edge moved one pixel left.
        XCTAssertEqual(edge1, edge0 - 1)
    }

    /// Wrap-around: scrolling by exactly one full cycle (text width + separator)
    /// renders identically to offset 0 — the loop is seamless.
    func testWrapAroundOneCycleIsIdenticalToOffsetZero() {
        let x = 8
        let maxWidth = 4 * glyphCellWidth
        let y = 4
        let title = "ABABABAB"
        let cycle = BitmapText.scrollCycleWidth(of: title)

        var base0 = solidBitmap(width: 90, height: 20, color: bgColor)
        var baseCycle = solidBitmap(width: 90, height: 20, color: bgColor)
        BitmapText.drawScrolling(title, from: skinWithAB(), onto: &base0, x: x, y: y, maxWidth: maxWidth, offset: 0)
        BitmapText.drawScrolling(title, from: skinWithAB(), onto: &baseCycle, x: x, y: y, maxWidth: maxWidth, offset: cycle)

        XCTAssertEqual(base0.pixels, baseCycle.pixels)
    }

    /// A glyph straddling the RIGHT edge is pixel-clipped: only its in-window
    /// columns are drawn, never beyond `x + maxWidth`. We choose a maxWidth that
    /// cuts a glyph in half and assert the in-window half is glyph color while the
    /// first out-of-window column stays background.
    func testPartialGlyphClippedAtRightEdge() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        let x = 10
        let y = 5
        // 2.5 cells wide: the third glyph cell is half inside, half outside.
        let maxWidth = 2 * glyphCellWidth + glyphCellWidth / 2

        BitmapText.drawScrolling(
            "AAAAAAAA", from: skinWithAB(), onto: &base, x: x, y: y, maxWidth: maxWidth, offset: 0
        )

        // Last in-window column is glyph color (the straddling glyph's left half).
        XCTAssertEqual(pixel(base, x: x + maxWidth - 1, y: y).0, colorA.0)
        // The first out-of-window column was never written.
        XCTAssertEqual(pixel(base, x: x + maxWidth, y: y).0, bgColor.0)
    }

    /// Likewise at the LEFT edge: a glyph partly scrolled off the left is clipped
    /// so nothing is ever written at a column `< x`. With offset 2 (less than one
    /// cell) the first cell is partly off-screen; the column just left of `x` stays
    /// background.
    func testPartialGlyphClippedAtLeftEdge() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        let x = 10
        let y = 5
        let maxWidth = 4 * glyphCellWidth

        BitmapText.drawScrolling(
            "AAAAAAAA", from: skinWithAB(), onto: &base, x: x, y: y, maxWidth: maxWidth, offset: 2
        )

        // Window left edge shows glyph color (the partly-scrolled first cell).
        XCTAssertEqual(pixel(base, x: x, y: y).0, colorA.0)
        // The column just left of the window was never written.
        XCTAssertEqual(pixel(base, x: x - 1, y: y).0, bgColor.0)
    }

    /// Short text (pixel width <= maxWidth) is STATIC: the offset is ignored, so
    /// any offset yields identical output (and the same as the plain `draw`).
    func testShortTextIgnoresOffsetAndDrawsStatic() {
        let x = 6
        let y = 5
        let maxWidth = 1000 // far wider than "AB"

        var byDraw = solidBitmap(width: 60, height: 20, color: bgColor)
        BitmapText.draw("AB", from: skinWithAB(), onto: &byDraw, x: x, y: y, maxWidth: maxWidth)

        var atZero = solidBitmap(width: 60, height: 20, color: bgColor)
        var atBig = solidBitmap(width: 60, height: 20, color: bgColor)
        BitmapText.drawScrolling("AB", from: skinWithAB(), onto: &atZero, x: x, y: y, maxWidth: maxWidth, offset: 0)
        BitmapText.drawScrolling("AB", from: skinWithAB(), onto: &atBig, x: x, y: y, maxWidth: maxWidth, offset: 37)

        // Static for any offset, and identical to the plain left-aligned draw.
        XCTAssertEqual(atZero.pixels, atBig.pixels)
        XCTAssertEqual(atZero.pixels, byDraw.pixels)
    }

    /// Empty text is a no-op: the base is unchanged for any offset.
    func testScrollingEmptyTextIsNoOp() {
        let original = solidBitmap(width: 60, height: 20, color: bgColor)
        var base = original
        BitmapText.drawScrolling("", from: skinWithAB(), onto: &base, x: 4, y: 5, maxWidth: 30, offset: 17)
        XCTAssertEqual(base.pixels, original.pixels)
    }

    // MARK: - 7. drawNumber (right-aligned integer field)
    //
    // `drawNumber` paints an integer RIGHT-ALIGNED into a fixed field of `digits`
    // numbers.bmp digit cells starting at (x, y) — the kbps / kHz number boxes.
    // Leading positions are BLANK (the classic look: no leading zeros), the value
    // is clipped to the low-order `digits` digits when it has more, and a negative
    // clamps to 0. These tests use ten distinct digit colors so a single landing
    // pixel proves which digit sprite was placed in which cell.

    /// A skin with `digit0...digit9` sprites, each a distinct solid color:
    /// `digitN -> (10*N, N, 100, 255)`.
    private func skinWithDigits() -> Skin {
        var digits: [String: DecodedBitmap] = [:]
        for n in 0...9 {
            digits["digit\(n)"] = solidBitmap(
                width: digitCellWidth,
                height: digitCellHeight,
                color: (UInt8(10 * n), UInt8(n), 100, 255)
            )
        }
        return makeSkin(sprites: ["numbers.bmp": digits])
    }

    /// The (red, green) landing color for `digitN`, mirroring `skinWithDigits`.
    private func digitColor(_ n: Int) -> (UInt8, UInt8) {
        (UInt8(10 * n), UInt8(n))
    }

    /// `44` in a 3-cell field sits RIGHT-ALIGNED in the right two cells; the left
    /// (leading) cell stays blank (background shows through).
    func testDrawNumberRightAlignsAndLeavesLeadingCellBlank() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        let x = 2, y = 3

        BitmapText.drawNumber(44, from: skinWithDigits(), onto: &base, x: x, y: y, digits: 3)

        // Cell 0 (leftmost) is a leading blank: background unchanged.
        XCTAssertEqual(pixel(base, x: x, y: y).0, bgColor.0)
        XCTAssertEqual(pixel(base, x: x, y: y).1, bgColor.1)
        XCTAssertEqual(pixel(base, x: x, y: y).2, bgColor.2)
        // Cell 1 holds the tens digit '4'.
        XCTAssertEqual(pixel(base, x: x + digitCellWidth, y: y).0, digitColor(4).0)
        XCTAssertEqual(pixel(base, x: x + digitCellWidth, y: y).1, digitColor(4).1)
        // Cell 2 holds the ones digit '4'.
        XCTAssertEqual(pixel(base, x: x + 2 * digitCellWidth, y: y).0, digitColor(4).0)
        XCTAssertEqual(pixel(base, x: x + 2 * digitCellWidth, y: y).1, digitColor(4).1)
    }

    /// `128` exactly fills a 3-cell field: digit '1','2','8' in cells 0,1,2.
    func testDrawNumberFillsFieldWhenDigitCountMatches() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        let x = 1, y = 2

        BitmapText.drawNumber(128, from: skinWithDigits(), onto: &base, x: x, y: y, digits: 3)

        XCTAssertEqual(pixel(base, x: x, y: y).0, digitColor(1).0)
        XCTAssertEqual(pixel(base, x: x, y: y).1, digitColor(1).1)
        XCTAssertEqual(pixel(base, x: x + digitCellWidth, y: y).0, digitColor(2).0)
        XCTAssertEqual(pixel(base, x: x + digitCellWidth, y: y).1, digitColor(2).1)
        XCTAssertEqual(pixel(base, x: x + 2 * digitCellWidth, y: y).0, digitColor(8).0)
        XCTAssertEqual(pixel(base, x: x + 2 * digitCellWidth, y: y).1, digitColor(8).1)
    }

    /// Zero renders as a single '0' in the rightmost cell; the leading cells stay
    /// blank (no leading zeros in the classic look).
    func testDrawNumberZeroIsSingleTrailingDigit() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        let x = 4, y = 1

        BitmapText.drawNumber(0, from: skinWithDigits(), onto: &base, x: x, y: y, digits: 3)

        // Two leading cells blank.
        XCTAssertEqual(pixel(base, x: x, y: y).0, bgColor.0)
        XCTAssertEqual(pixel(base, x: x + digitCellWidth, y: y).0, bgColor.0)
        // Rightmost cell holds '0'.
        XCTAssertEqual(pixel(base, x: x + 2 * digitCellWidth, y: y).0, digitColor(0).0)
        XCTAssertEqual(pixel(base, x: x + 2 * digitCellWidth, y: y).1, digitColor(0).1)
    }

    /// A value with MORE digits than the field shows the LOW-order `digits` digits
    /// and — the clip-safety check — never writes past the field width: the column
    /// just past the field stays untouched. `1411` in a 2-field shows '1','1'.
    func testDrawNumberClipsToLowOrderDigitsAndNeverOverflowsField() {
        var base = solidBitmap(width: 120, height: 20, color: bgColor)
        let x = 5, y = 3
        let digits = 2

        BitmapText.drawNumber(1411, from: skinWithDigits(), onto: &base, x: x, y: y, digits: digits)

        // Low-order two digits of 1411 are "11": cell 0 '1', cell 1 '1'.
        XCTAssertEqual(pixel(base, x: x, y: y).0, digitColor(1).0)
        XCTAssertEqual(pixel(base, x: x, y: y).1, digitColor(1).1)
        XCTAssertEqual(pixel(base, x: x + digitCellWidth, y: y).0, digitColor(1).0)
        XCTAssertEqual(pixel(base, x: x + digitCellWidth, y: y).1, digitColor(1).1)
        // The column at the field's right edge (x + digits*cellWidth) is OUTSIDE
        // the field and must stay background — the overflow guard.
        let pastFieldX = x + digits * digitCellWidth
        XCTAssertEqual(pixel(base, x: pastFieldX, y: y).0, bgColor.0)
        XCTAssertEqual(pixel(base, x: pastFieldX, y: y).1, bgColor.1)
        XCTAssertEqual(pixel(base, x: pastFieldX, y: y).2, bgColor.2)
        // Well past the field, still background.
        XCTAssertEqual(pixel(base, x: pastFieldX + digitCellWidth, y: y).0, bgColor.0)
    }

    /// A negative value clamps to 0: renders as a single '0' in the rightmost cell,
    /// leading cells blank — identical to drawing 0.
    func testDrawNumberNegativeClampsToZero() {
        var negative = solidBitmap(width: 80, height: 20, color: bgColor)
        var zero = solidBitmap(width: 80, height: 20, color: bgColor)
        let x = 3, y = 2

        BitmapText.drawNumber(-7, from: skinWithDigits(), onto: &negative, x: x, y: y, digits: 3)
        BitmapText.drawNumber(0, from: skinWithDigits(), onto: &zero, x: x, y: y, digits: 3)

        XCTAssertEqual(negative.pixels, zero.pixels)
    }

    /// drawNumber with no numbers.bmp sheet advances blank and never crashes.
    func testDrawNumberWithNoNumbersSheetDoesNotCrash() {
        var base = solidBitmap(width: 80, height: 20, color: bgColor)
        BitmapText.drawNumber(192, from: makeSkin(sprites: [:]), onto: &base, x: 0, y: 0, digits: 3)
        XCTAssertEqual(pixel(base, x: 0, y: 0).0, bgColor.0)
        XCTAssertEqual(base.pixels.count, 80 * 20 * 4)
    }
}
