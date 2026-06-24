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
            if let sprite = skin.sprite(sheet: "text.bmp", name: glyphName(for: character)) {
                SkinCanvas.overlay(sprite, onto: &base, x: penX, y: y)
            }
            // Fixed-cell font: every character advances by one cell, whether or
            // not it had a glyph (missing glyph -> blank advance).
            penX += glyphCellWidth
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

    // MARK: - Helpers

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

    /// A stable, identifier-safe name for a font glyph cell, matching the
    /// convention authored in `SkinKit.SpriteCoordinates`: letters/digits map to
    /// `glyph_<char>`; any other printable character maps to `glyph_u<hex>`,
    /// where `<hex>` is the lowercased base-16 unicode scalar value.
    private static func glyphName(for character: Character) -> String {
        if character.isLetter || character.isNumber {
            return "glyph_\(character)"
        }
        guard let scalar = character.unicodeScalars.first else {
            return "glyph_u0"
        }
        return "glyph_u\(String(scalar.value, radix: 16))"
    }
}
