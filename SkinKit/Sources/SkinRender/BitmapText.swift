import Foundation
import SkinKit

// MARK: - BitmapText
//
// Pure bitmap-font text rendering for the classic main window. It needs NO
// graphics framework: drawing a string is looking up each character's glyph
// sprite from the skin's `text.bmp` sheet and overlaying it onto a base buffer
// through the shared `SkinCanvas.overlay` seam, advancing left to right by the
// fixed glyph cell width.
//
// The classic bitmap font is a fixed 5x6 cell grid and is UPPERCASE-only, so
// input is uppercased before lookup. A character with no glyph sprite (e.g. a
// space, or any character the font does not model) renders blank and still
// advances by one cell — so text stays aligned and nothing ever traps.
//
// Sprite names follow the convention authored in
// `SkinKit.SpriteCoordinates`: letters/digits are `glyph_<char>` and other
// printable characters are `glyph_u<hex>` (the lowercased base-16 unicode
// scalar). The numeric time uses `numbers.bmp`'s `digit0...digit9` sprites.

public enum BitmapText {

    // MARK: - Metrics
    //
    // These mirror the fixed cell sizes declared in `SpriteCoordinates`. They
    // are the per-character advances, kept here so a missing glyph can advance
    // by the right amount without needing the sprite itself.

    /// text.bmp fixed glyph cell width (the per-character advance).
    private static let glyphCellWidth = 5
    /// numbers.bmp digit cell width (the per-digit advance).
    private static let digitCellWidth = 9
    /// Horizontal gap reserved for the colon between MM and SS, in pixels.
    // provisional — tune at render
    private static let timeColonGap = 5

    /// Separator appended after the title before it wraps in the scrolling
    /// marquee, so the loop reads as a gap rather than the title abutting itself.
    /// Three blank cells: the characters have no glyph (space is not modelled), so
    /// they render as empty space and only contribute their fixed-cell advance —
    /// exactly the gap a classic marquee shows between repeats. Kept as a string
    /// (not a raw width) so its width is derived from the same per-cell advance as
    /// every other character, keeping the metric a single source of truth.
    private static let scrollSeparator = "   "

    // MARK: - Draw text

    /// Draw `text` left-to-right using the skin's `text.bmp` glyph sprites, onto
    /// `base` starting at top-left `(x, y)`, clipped to the title display region
    /// `[x, x + maxWidth)`.
    ///
    /// Input is uppercased (the classic font is uppercase-only). A character with
    /// no glyph sprite advances by the glyph cell width (rendering blank) and
    /// never crashes. Clipping at the base edges is handled by the overlay seam.
    ///
    /// `maxWidth` bounds the title to its display region so a long string cannot
    /// bleed past the region into the rest of the window. Drawing advances
    /// left-to-right and stops once a glyph cell would extend beyond
    /// `x + maxWidth`; a glyph that only partially fits is skipped entirely (no
    /// partial-glyph clipping). A non-positive `maxWidth` draws nothing.
    public static func draw(
        _ text: String,
        from skin: Skin,
        onto base: inout DecodedBitmap,
        x: Int,
        y: Int,
        maxWidth: Int
    ) {
        let regionEnd = x + maxWidth
        var penX = x
        for character in text.uppercased() {
            // Stop at the region edge: once this glyph cell would extend past
            // x + maxWidth, no further (left-to-right) glyph can fit either.
            if penX + glyphCellWidth > regionEnd {
                break
            }
            if let sprite = skin.sprite(sheet: "text.bmp", name: SpriteCoordinates.glyphName(for: character)) {
                SkinCanvas.overlay(sprite, onto: &base, x: penX, y: y)
            }
            // Fixed-cell font: every character advances by one cell, whether or
            // not it had a glyph (missing glyph -> blank advance).
            penX += glyphCellWidth
        }
    }

    // MARK: - Scrolling marquee

    /// The rendered pixel width of `text`: one fixed glyph cell per character,
    /// whether or not that character has a glyph sprite. This mirrors exactly how
    /// `draw` advances the pen, so callers can decide whether a title overflows
    /// its display region and how far it must scroll to loop.
    public static func pixelWidth(of text: String) -> Int {
        text.count * glyphCellWidth
    }

    /// The length of one full scroll loop for `text`, in pixels: the text's pixel
    /// width plus the fixed separator gap appended before it repeats. Advancing
    /// the scroll offset by exactly this many pixels returns to the start, so a
    /// caller can keep the offset bounded (and a seamless loop is `offset %
    /// scrollCycleWidth`).
    public static func scrollCycleWidth(of text: String) -> Int {
        pixelWidth(of: text) + pixelWidth(of: scrollSeparator)
    }

    /// Draw `text` as a horizontally scrolling marquee, shifted left by `offset`
    /// pixels, clipped to the display region `[x, x + maxWidth)`.
    ///
    /// The title is followed by a fixed separator gap and then repeats, so the
    /// scroll loops seamlessly: rendering at `offset` and at `offset +
    /// scrollCycleWidth(of:)` is identical. Glyphs that straddle the left or right
    /// clip edge are PIXEL-clipped — never a pixel written at a column `< x` or
    /// `>= x + maxWidth`.
    ///
    /// When the title fits (its `pixelWidth` is `<= maxWidth`), there is nothing to
    /// scroll: `offset` is ignored and the title is drawn STATIC, left-aligned,
    /// identically to `draw`. Empty text and a non-positive `maxWidth` draw
    /// nothing. Like `draw`, input is uppercased and a missing glyph advances blank.
    public static func drawScrolling(
        _ text: String,
        from skin: Skin,
        onto base: inout DecodedBitmap,
        x: Int,
        y: Int,
        maxWidth: Int,
        offset: Int
    ) {
        guard maxWidth > 0 else { return }

        // Fits the region -> nothing to scroll: draw static, ignoring the offset.
        // (Empty text has width 0, so it takes this branch and draws nothing.)
        if pixelWidth(of: text) <= maxWidth {
            draw(text, from: skin, onto: &base, x: x, y: y, maxWidth: maxWidth)
            return
        }

        // One loop unit is the title plus the separator gap; the marquee is this
        // unit repeated. Normalize the offset into [0, cycle) so the loop is
        // seamless and the math stays bounded for any caller-supplied offset.
        let cycle = scrollCycleWidth(of: text)
        let normalized = ((offset % cycle) + cycle) % cycle

        let regionStart = x
        let regionEnd = x + maxWidth

        // Lay TWO copies of the loop unit end to end, starting shifted left by the
        // normalized offset. Two copies guarantee the window is fully covered for
        // any offset in [0, cycle): the first copy's tail plus the second copy's
        // head always span at least one full cycle past the window's left edge.
        let unit = Array((text + scrollSeparator).uppercased())
        var penX = x - normalized
        for _ in 0..<2 {
            for character in unit {
                // Skip cells entirely left of or right of the window; pixel-clip
                // the ones that straddle an edge.
                if penX + glyphCellWidth > regionStart && penX < regionEnd {
                    if let sprite = skin.sprite(
                        sheet: "text.bmp", name: SpriteCoordinates.glyphName(for: character)
                    ) {
                        overlayColumnClipped(
                            sprite, onto: &base, x: penX, y: y,
                            clipLeft: regionStart, clipRight: regionEnd
                        )
                    }
                }
                penX += glyphCellWidth
                // Past the right edge: no later cell in this (left-to-right) pass
                // can fall inside the window, so stop early.
                if penX >= regionEnd { break }
            }
            if penX >= regionEnd { break }
        }
    }

    // MARK: - Draw time

    /// Draw a zero-padded MM:SS-style time using `numbers.bmp`'s `digit0...digit9`
    /// sprites, onto `base` at top-left `(x, y)`.
    ///
    /// Minutes and seconds are each rendered as two zero-padded digits with a
    /// reserved colon gap between them. A missing digit sprite advances blank and
    /// never crashes; edge clipping is handled by the overlay seam.
    public static func drawTime(
        minutes: Int,
        seconds: Int,
        from skin: Skin,
        onto base: inout DecodedBitmap,
        x: Int,
        y: Int
    ) {
        var penX = x
        penX = drawTwoDigits(minutes, from: skin, onto: &base, x: penX, y: y)
        // Reserve the colon gap (the colon itself is not drawn from numbers.bmp).
        penX += timeColonGap
        _ = drawTwoDigits(seconds, from: skin, onto: &base, x: penX, y: y)
    }

    // MARK: - Draw number (right-aligned integer field)

    /// Draw `value` as an integer RIGHT-ALIGNED in a field of `digits`
    /// `numbers.bmp` digit cells, with the field's top-left at `(x, y)`. This is
    /// the kbps / kHz number-box renderer (reusing the same digit-sprite path as
    /// `drawTime`).
    ///
    /// Layout: the field is `digits` cells wide, each `digitCellWidth` px, filled
    /// from the RIGHT. The value's decimal digits occupy the rightmost cells; any
    /// LEADING cells are left BLANK — the classic kbps/kHz look shows no leading
    /// zeros, so e.g. `44` in a 3-field reads as a blank cell then "44", and `0`
    /// reads as a blank-blank-"0".
    ///
    /// Bounds / clip safety:
    /// - A NEGATIVE value clamps to 0 (no minus sign in the classic boxes).
    /// - A value with MORE digits than the field shows the LOW-order `digits`
    ///   digits (value modulo 10^digits), so it NEVER writes past the field width.
    ///   A synthesized WAV reports a large uncompressed bitrate (e.g. ~1411 kbps
    ///   for 44.1k/16-bit/stereo); in a 3-cell kbps field that renders the low
    ///   three digits "411" rather than overflowing into the kHz box.
    /// - A non-positive `digits` draws nothing.
    /// - A missing digit sprite advances blank and never crashes; edge clipping is
    ///   handled by the overlay seam.
    public static func drawNumber(
        _ value: Int,
        from skin: Skin,
        onto base: inout DecodedBitmap,
        x: Int,
        y: Int,
        digits: Int
    ) {
        guard digits > 0 else { return }

        // Negatives clamp to 0 (no sign glyph in the classic number boxes).
        let nonNegative = max(0, value)

        // Decompose into per-cell decimal digits, RIGHT-aligned: index 0 is the
        // rightmost (ones) cell, index `digits-1` the leftmost. `cellDigit` is the
        // digit to draw, or nil for a leading-blank cell. Clipping to the field
        // width is implicit: we only ever produce `digits` cells, so a value with
        // more digits keeps only its low-order `digits` (the high digits are never
        // emitted), which is exactly the overflow guard.
        var remaining = nonNegative
        var cellDigits = [Int?](repeating: nil, count: digits)
        for index in 0..<digits {
            cellDigits[index] = remaining % 10
            remaining /= 10
            // Once the value is exhausted, the higher cells stay nil (blank) —
            // except cell 0 always shows at least a single '0' for value 0, which
            // the first iteration already set.
            if remaining == 0 { break }
        }

        // Paint left-to-right: cell `column` (0 = leftmost) maps to digit index
        // `digits - 1 - column`. A nil cell is a leading blank (skip, just advance).
        var penX = x
        for column in 0..<digits {
            let digitIndex = digits - 1 - column
            if let digit = cellDigits[digitIndex],
               let sprite = skin.sprite(sheet: "numbers.bmp", name: "digit\(digit)") {
                SkinCanvas.overlay(sprite, onto: &base, x: penX, y: y)
            }
            penX += digitCellWidth
        }
    }

    // MARK: - Helpers

    /// Overlay `sprite` onto `base` at top-left `(x, y)`, opaque overwrite, but
    /// writing ONLY the columns inside `[clipLeft, clipRight)` — the horizontal
    /// clip window. Rows are still clipped to the base bounds (top-left origin).
    ///
    /// This is the per-pixel left/right clip the scrolling marquee needs: a glyph
    /// straddling either edge draws only its in-window columns, never a pixel at a
    /// column `< clipLeft` or `>= clipRight`. Like `SkinCanvas.overlay` it skips
    /// silently on a size-inconsistent buffer so a malformed sprite can never trap.
    private static func overlayColumnClipped(
        _ sprite: DecodedBitmap,
        onto base: inout DecodedBitmap,
        x: Int,
        y: Int,
        clipLeft: Int,
        clipRight: Int
    ) {
        guard base.pixels.count == base.width * base.height * 4 else { return }
        guard sprite.pixels.count == sprite.width * sprite.height * 4 else { return }

        let canvasWidth = base.width
        let canvasHeight = base.height

        // Destination column range, clipped to BOTH the canvas bounds and the
        // [clipLeft, clipRight) window, then mapped back into sprite columns.
        let destStart = max(0, max(x, clipLeft))
        let destEnd = min(canvasWidth, min(x + sprite.width, clipRight))
        guard destStart < destEnd else { return }
        let startColumn = destStart - x // first visible sprite column

        // Visible row range within the sprite, clipped to the canvas.
        let startRow = max(0, -y)
        let endRow = min(sprite.height, canvasHeight - y)
        guard startRow < endRow else { return }

        let visibleWidth = destEnd - destStart
        let byteCount = visibleWidth * 4

        var pixels = base.pixels
        for row in startRow..<endRow {
            let spriteRowStart = (row * sprite.width + startColumn) * 4
            let canvasY = y + row
            let canvasRowStart = (canvasY * canvasWidth + destStart) * 4
            pixels.replaceSubrange(
                canvasRowStart..<(canvasRowStart + byteCount),
                with: sprite.pixels[spriteRowStart..<(spriteRowStart + byteCount)]
            )
        }
        base = DecodedBitmap(width: canvasWidth, height: canvasHeight, pixels: pixels)
    }

    /// Draws `value` as exactly two zero-padded digits starting at `(x, y)` and
    /// returns the pen x position just past them. A value outside 0...99 is
    /// reduced modulo 100 so the field stays two digits.
    private static func drawTwoDigits(
        _ value: Int,
        from skin: Skin,
        onto base: inout DecodedBitmap,
        x: Int,
        y: Int
    ) -> Int {
        let clamped = ((value % 100) + 100) % 100 // keep within 0...99, no negatives
        let tens = clamped / 10
        let ones = clamped % 10

        var penX = x
        for digit in [tens, ones] {
            if let sprite = skin.sprite(sheet: "numbers.bmp", name: "digit\(digit)") {
                SkinCanvas.overlay(sprite, onto: &base, x: penX, y: y)
            }
            penX += digitCellWidth
        }
        return penX
    }
}
