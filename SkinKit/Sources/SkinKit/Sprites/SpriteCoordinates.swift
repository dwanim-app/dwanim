import Foundation

// MARK: - SpriteCoordinates
//
// Clean-room sprite rectangles for the classic `.wsz` skin format, authored
// from the public format specification. These are factual descriptions of where
// each sprite lives inside its sheet — the pixel offsets that the format
// mandates — and are not transcribed from any proprietary product source.
//
// Source: the public classic `.wsz` skin format specification.
//
// Convention: top-left origin, x rightward / y downward, pixels. Sheet keys are
// lowercased filenames as stored in the archive.

/// Static map from sprite-sheet filename to the sprites packed within it, for
/// the classic main player window.
public enum SpriteCoordinates {

    /// Sheet filename (lowercased, e.g. `"cbuttons.bmp"`) -> sprites it contains.
    ///
    /// SCOPE: the **main player window** only. The equalizer and playlist
    /// windows are deferred to a future increment.
    // TODO: future increment — add eqmain.bmp / eq_ex.bmp (equalizer window)
    //       and pledit.bmp (playlist window) sprite tables.
    public static let mainWindow: [String: [SpriteRect]] = [
        "main.bmp": mainBackground,
        "cbuttons.bmp": controlButtons,
        "titlebar.bmp": titlebar,
        "shufrep.bmp": shuffleRepeat,
        "posbar.bmp": positionBar,
        "volume.bmp": volume,
        "balance.bmp": balance,
        "monoster.bmp": monoStereo,
        "playpaus.bmp": playPauseStatus,
        "numbers.bmp": numbers,
        "text.bmp": text
    ]

    // MARK: - main.bmp (window background)

    /// The full window background, used whole at its natural size.
    private static let mainBackground: [SpriteRect] = [
        SpriteRect(name: "background", x: 0, y: 0, width: 275, height: 116)
    ]

    // MARK: - cbuttons.bmp (transport buttons)
    //
    // Five transport buttons, each 23x18, in two rows: the top row holds the
    // normal (released) state and the bottom row the pressed state. Play and
    // pause share the same column footprint in the format; both are modelled.

    private static let controlButtons: [SpriteRect] = [
        // Released states (top row).
        SpriteRect(name: "previous", x: 0,  y: 0, width: 23, height: 18),
        SpriteRect(name: "play",     x: 23, y: 0, width: 23, height: 18),
        SpriteRect(name: "pause",    x: 46, y: 0, width: 23, height: 18),
        SpriteRect(name: "stop",     x: 69, y: 0, width: 23, height: 18),
        SpriteRect(name: "next",     x: 92, y: 0, width: 23, height: 18),
        // Pressed states (bottom row).
        SpriteRect(name: "previousPressed", x: 0,  y: 18, width: 23, height: 18),
        SpriteRect(name: "playPressed",     x: 23, y: 18, width: 23, height: 18),
        SpriteRect(name: "pausePressed",    x: 46, y: 18, width: 23, height: 18),
        SpriteRect(name: "stopPressed",     x: 69, y: 18, width: 23, height: 18),
        SpriteRect(name: "nextPressed",     x: 92, y: 18, width: 23, height: 18)
    ]

    // MARK: - titlebar.bmp (title bar + window buttons)
    //
    // Holds the active/inactive title bars and the small window-chrome buttons
    // (close, minimize, shade/unshade) in their normal and pressed states.

    private static let titlebar: [SpriteRect] = [
        SpriteRect(name: "titleBarActive",   x: 27, y: 0,  width: 275, height: 14),
        SpriteRect(name: "titleBarInactive", x: 27, y: 15, width: 275, height: 14),
        SpriteRect(name: "close",            x: 18, y: 0,  width: 9,   height: 9),
        SpriteRect(name: "closePressed",     x: 18, y: 9,  width: 9,   height: 9),
        SpriteRect(name: "minimize",         x: 9,  y: 0,  width: 9,   height: 9),
        SpriteRect(name: "minimizePressed",  x: 9,  y: 9,  width: 9,   height: 9),
        SpriteRect(name: "shade",            x: 0,  y: 18, width: 9,   height: 9),
        SpriteRect(name: "shadePressed",     x: 9,  y: 18, width: 9,   height: 9)
    ]

    // MARK: - shufrep.bmp (shuffle + repeat toggles)
    //
    // Two toggle buttons, each with off/on states and their pressed variants.

    private static let shuffleRepeat: [SpriteRect] = [
        SpriteRect(name: "repeatOff",        x: 0,  y: 0,  width: 28, height: 15),
        SpriteRect(name: "repeatOn",         x: 0,  y: 15, width: 28, height: 15),
        SpriteRect(name: "repeatOffPressed", x: 0,  y: 30, width: 28, height: 15),
        SpriteRect(name: "repeatOnPressed",  x: 0,  y: 45, width: 28, height: 15),
        SpriteRect(name: "shuffleOff",        x: 28, y: 0,  width: 47, height: 15),
        SpriteRect(name: "shuffleOn",         x: 28, y: 15, width: 47, height: 15),
        SpriteRect(name: "shuffleOffPressed", x: 28, y: 30, width: 47, height: 15),
        SpriteRect(name: "shuffleOnPressed",  x: 28, y: 45, width: 47, height: 15)
    ]

    // MARK: - posbar.bmp (seek/position bar)
    //
    // The position-bar track plus the slider thumb in normal and pressed states.

    private static let positionBar: [SpriteRect] = [
        SpriteRect(name: "track",        x: 0,   y: 0, width: 248, height: 10),
        SpriteRect(name: "thumb",        x: 248, y: 0, width: 29,  height: 10),
        SpriteRect(name: "thumbPressed", x: 278, y: 0, width: 29,  height: 10)
    ]

    // MARK: - volume.bmp (volume slider)
    //
    // 28 stacked position frames (one per level), each 68 wide and 15 tall,
    // stacked from y=0. The slider thumb is baked into each frame, so there is no
    // separate thumb sprite. 28 * 15 = 420, exactly filling the standard sheet
    // height (some skins ship a slightly taller 433px sheet; the extra rows are
    // unused and the frames still start at y=0).

    private static let volume: [SpriteRect] = sliderBackgrounds(count: 28, width: 68, height: 15)

    // MARK: - balance.bmp (balance slider)
    //
    // Same vertical shape as the volume sheet — 28 stacked position frames from
    // y=0, each 15 tall, with the thumb baked in (no separate thumb sprite) —
    // but the balance frame is NARROWER than volume's: 47 wide, not 68. The
    // balance knob graphic only occupies the left portion of the strip, so the
    // canonical sheet is authored 47 wide. A 47-wide frame is in-bounds on both
    // 47-wide and 68-wide balance sheets; a 68-wide frame would overrun the many
    // skins that ship balance at 47px. 28 * 15 = 420, the standard content
    // height (some skins ship a slightly taller 433px sheet; the extra rows are
    // unused and the frames still start at y=0).

    private static let balance: [SpriteRect] = sliderBackgrounds(count: 28, width: 47, height: 15)

    // MARK: - monoster.bmp (mono / stereo indicators)
    //
    // Mono and stereo labels, each with a lit (active) and dim (inactive) state.

    private static let monoStereo: [SpriteRect] = [
        SpriteRect(name: "stereoActive",   x: 0,  y: 0,  width: 29, height: 12),
        SpriteRect(name: "stereoInactive", x: 0,  y: 12, width: 29, height: 12),
        SpriteRect(name: "monoActive",     x: 29, y: 0,  width: 27, height: 12),
        SpriteRect(name: "monoInactive",   x: 29, y: 12, width: 27, height: 12)
    ]

    // MARK: - playpaus.bmp (playback status indicator)
    //
    // Standard sheet is 42x9. It holds the small play / pause / stop status
    // glyphs shown beside the time display (each 9x9, laid out left to right),
    // followed by the narrow "work" (buffering) indicator bars at the right.
    // Every rect is 9px tall and must fit within 42 wide.
    //
    // The work-indicator bars are narrow 3px frames packed into the space left of
    // the right edge: a play-state bar and a pause-state bar that bridge between
    // the play and pause glyphs while buffering. Their exact x/width are not
    // pinned by the public spec, so conservative fitting values are used.

    private static let playPauseStatus: [SpriteRect] = [
        SpriteRect(name: "play",      x: 0,  y: 0, width: 9, height: 9),
        SpriteRect(name: "pause",     x: 9,  y: 0, width: 9, height: 9),
        SpriteRect(name: "stop",      x: 18, y: 0, width: 9, height: 9),
        // provisional — tune at render
        SpriteRect(name: "workIndicatorPlay",  x: 36, y: 0, width: 3, height: 9),
        // provisional — tune at render
        SpriteRect(name: "workIndicatorPause", x: 39, y: 0, width: 3, height: 9)
    ]

    // MARK: - numbers.bmp (time digits 0-9)
    //
    // Ten digit glyphs laid out left to right, each 9x13.

    private static let numbers: [SpriteRect] = (0...9).map { digit in
        SpriteRect(name: "digit\(digit)", x: digit * 9, y: 0, width: 9, height: 13)
    }

    // MARK: - text.bmp (bitmap font)
    //
    // A fixed-cell 5x6 bitmap font. The glyph grid is 31 columns wide across 3
    // rows; each declared sprite is one character cell, named by the character it
    // renders. Only the printable subset needed by the main window is modelled.

    private static let text: [SpriteRect] = bitmapFont()

    // MARK: - Generators

    /// Builds `count` vertically stacked slider background frames named
    /// `level0 ... level(count-1)`, top to bottom.
    private static func sliderBackgrounds(count: Int, width: Int, height: Int) -> [SpriteRect] {
        (0..<count).map { level in
            SpriteRect(name: "level\(level)", x: 0, y: level * height, width: width, height: height)
        }
    }

    /// Builds the printable cells of the 5x6 fixed-cell bitmap font. The font is
    /// arranged as three rows of 31 cells; this models the alphanumerics,
    /// space, and the punctuation used by the main window.
    private static func bitmapFont() -> [SpriteRect] {
        // Row-major character map of the font sheet (top-left origin). Unused
        // cells are represented by nil and skipped.
        let rows: [[Character?]] = [
            Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ\"@ "),
            Array("0123456789….:()-'!_+\\/[]^&%,=$#"),
            Array("ÅÖÄ?* ")
        ]
        let cellWidth = 5
        let cellHeight = 6
        var rects: [SpriteRect] = []
        for (rowIndex, row) in rows.enumerated() {
            for (colIndex, character) in row.enumerated() {
                guard let character, character != " " else { continue }
                rects.append(
                    SpriteRect(
                        name: glyphName(for: character),
                        x: colIndex * cellWidth,
                        y: rowIndex * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                )
            }
        }
        return rects
    }

    /// A stable, identifier-safe name for a font glyph cell. The single source of
    /// truth for glyph naming, shared by the render-side text drawer
    /// (`SkinRender.BitmapText`): letters/digits map to `glyph_<char>`; any other
    /// printable character maps to `glyph_u<hex>`, where `<hex>` is the lowercased
    /// base-16 unicode scalar value.
    ///
    /// Non-trapping: a character with no unicode scalar (which `Character` does
    /// not normally produce) falls back to `glyph_u0` rather than crashing.
    public static func glyphName(for character: Character) -> String {
        if character.isLetter || character.isNumber {
            return "glyph_\(character)"
        }
        guard let scalar = character.unicodeScalars.first else {
            return "glyph_u0"
        }
        return "glyph_u\(String(scalar.value, radix: 16))"
    }
}
