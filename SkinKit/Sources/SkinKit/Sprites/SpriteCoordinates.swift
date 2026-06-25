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
    /// SCOPE: the **main player window** only. The playlist window lives in its
    /// own table (`playlistWindow`); the equalizer window in `equalizerWindow`.
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

    /// Sheet filename (lowercased) -> sprites it contains, for the classic
    /// **playlist (PLEDIT) window**.
    ///
    /// SCOPE: the resizable playlist window FRAME — the chrome that the window
    /// composites from `pledit.bmp` (title bar, side edges, bottom frame, and the
    /// small scrollbar handle). The row-text colors/font come from `pledit.txt`
    /// (parsed separately into `PlaylistColors`), not from this sheet.
    public static let playlistWindow: [String: [SpriteRect]] = [
        "pledit.bmp": playlistFrame
    ]

    /// Sheet filename (lowercased) -> sprites it contains, for the classic
    /// **equalizer (EQ) window**.
    ///
    /// SCOPE: the fixed-size 275x116 equalizer window composited from
    /// `eqmain.bmp` — the window background (EQ face), the active/inactive title
    /// bars, the shared slider THUMB (normal + pressed) used by the preamp and the
    /// ten band sliders, and the ON / AUTO toggle buttons (each off + on).
    ///
    /// The windowshade variant lives in `eq_ex.bmp` and is DEFERRED (it is not
    /// keyed here). The colored band-graph line gradient and the preset/text
    /// micro-region are also DEFERRED — see the comment block on `equalizerFace`.
    public static let equalizerWindow: [String: [SpriteRect]] = [
        "eqmain.bmp": equalizerFace
    ]

    // MARK: - pledit.bmp (playlist window frame)
    //
    // Clean-room from the public PLEDIT layout. The classic playlist window is a
    // resizable frame composited from edge/corner pieces packed into the top and
    // left portions of `pledit.bmp`, plus a tiny scrollbar handle.
    //
    // FIT BUDGET (balance-bug lesson): the real `pledit.bmp` was measured across
    // the ~200-skin corpus. Width is 280 in 188/191 skins (smallest non-degenerate
    // 276); height is 186 (modal) or 190, smallest 186. So EVERY rect here is kept
    // inside 276 x 186 — the smallest real sheet — so none is silently dropped by
    // `SpriteCutter` on a real skin (an out-of-bounds rect would make the piece
    // vanish, exactly the failure the balance/volume pins guard against). The
    // public layout's native pieces all live well inside that box; we deliberately
    // do NOT declare any rect that would overrun 276 x 186.
    //
    // Layout convention (top-left origin):
    //   * Title-bar row, y = 0, height 20: a left corner, a NARROW tiling texture
    //     strip, a CENTERED title piece (the baked "playlist title" art, drawn
    //     ONCE), more narrow texture, and a right corner. The active (focused)
    //     title strip is the top row; the inactive strip is the next row down
    //     (y = 21). The title piece is the bitmap label that must NOT be tiled
    //     (tiling it is the "repeated title" bug); the narrow fill strip is the
    //     tileable texture, drawn on BOTH sides of the title to span whatever
    //     width the window is stretched to. In the public PLEDIT top row the
    //     title piece is ~100px wide at x = 26, with the tileable fill texture in
    //     the ~25px band at x = 127 (between the title and the right corner); the
    //     corners are ~25px.
    //   * Side edges, height 29, tiled vertically down the window body: the left
    //     edge at x = 0 and the right edge just to its right, taken from the rows
    //     below the title bar.
    //   * Bottom frame, height 38: a bottom-left corner, a tiled bottom fill, and a
    //     bottom-right corner. The bottom-right corner also carries the lower
    //     "draggable"/resize title strip and the resize affordance.
    //   * Scrollbar handle: a small knob drawn in the right edge track.
    //
    // DEFERRED (documented, not modelled here): the playlist action buttons
    // (add / remove / select / misc / list menus) and the time/visualizer
    // mini-display live in the bottom-right region as tiny 8x18-class micro
    // sprites whose exact packing the public spec leaves under-pinned; they are
    // NOT needed to composite the resizable frame in the next increment and are
    // intentionally left to a later pass. Pieces are sized to FIT 276 x 186, not
    // to reproduce every micro-button.

    private static let playlistFrame: [SpriteRect] = [
        // --- Title bar (top row, active), y = 0, height 20 ---
        SpriteRect(name: "titleBarLeftCorner",      x: 0,   y: 0,  width: 25,  height: 20),
        // Centered title art (the baked "playlist title" label), drawn ONCE — it
        // must NOT be tiled. ~100px wide at x = 26 per the public PLEDIT layout.
        SpriteRect(name: "titleBarTitleActive",     x: 26,  y: 0,  width: 100, height: 20),
        // NARROW tileable texture strip (NOT the title text) — the tile drawn on
        // both sides of the title to span the stretched width.
        SpriteRect(name: "titleBarFillActive",      x: 127, y: 0,  width: 25,  height: 20),
        SpriteRect(name: "titleBarRightCorner",     x: 153, y: 0,  width: 25,  height: 20),
        // --- Title bar (inactive row), y = 21, height 20 ---
        SpriteRect(name: "titleBarLeftCornerInactive",  x: 0,   y: 21, width: 25,  height: 20),
        SpriteRect(name: "titleBarTitleInactive",        x: 26,  y: 21, width: 100, height: 20),
        SpriteRect(name: "titleBarFillInactive",         x: 127, y: 21, width: 25,  height: 20),
        SpriteRect(name: "titleBarRightCornerInactive",  x: 153, y: 21, width: 25,  height: 20),

        // --- Side edges (tiled vertically down the body), height 29 ---
        // Taken from the band below the title bar. Left edge and the narrower
        // right edge (which carries the scrollbar track) sit side by side.
        SpriteRect(name: "leftEdge",  x: 0,  y: 42, width: 25, height: 29),
        SpriteRect(name: "rightEdge", x: 26, y: 42, width: 20, height: 29),

        // --- Bottom frame, height 38, taken from the lower band (y = 72) ---
        SpriteRect(name: "bottomLeftCorner",  x: 0,   y: 72, width: 125, height: 38),
        // Centre fill, tiled horizontally across the stretched bottom.
        SpriteRect(name: "bottomFill",        x: 126, y: 72, width: 25,  height: 38),
        // Right corner carries the resize affordance + lower draggable strip.
        SpriteRect(name: "bottomRightCorner", x: 150, y: 72, width: 125, height: 38),

        // --- Scrollbar handle (small knob in the right-edge track) ---
        SpriteRect(name: "scrollHandle", x: 52, y: 53, width: 8, height: 18)
    ]

    // MARK: - eqmain.bmp (equalizer window)
    //
    // Clean-room from the public EQ-window layout. The classic equalizer is a
    // fixed-size 275x116 window whose face plus all its control sprites are
    // packed into ONE vertically-stacked sheet, `eqmain.bmp`.
    //
    // FIT BUDGET (balance/volume/posbar lesson): the real `eqmain.bmp` was
    // measured across the ~200-skin corpus (194 carried it). Width is 275 in
    // 189/194 skins (smallest non-degenerate 275, the dominant value). Height is
    // the interesting axis: it is 315 in 169 skins (modal/canonical) and >=292 in
    // 178 skins, but a minority ship the sheet TRUNCATED — 164 (4), 163 (6), 134
    // (1), and a hard floor of 116 (4). Those truncated sheets contain ONLY the
    // top band of the layout (the 275x116 EQ face, sometimes plus the colored
    // band-graph strip just below it); the author simply omitted the lower sprite
    // rows. The absolute smallest real `eqmain.bmp` is therefore 275 x 116.
    //
    // This is the posbar situation, not the balance situation: the canonical
    // sheet genuinely packs the title bars / thumb / buttons in the rows BELOW
    // y=116, so we CANNOT shrink the whole sheet to 116 without throwing those
    // sprites away on the 87% of skins that ship them. The discipline applied:
    //   * The window BACKGROUND (the EQ face the window always needs) is pinned to
    //     275x116 at y=0 — in-bounds on EVERY real eqmain.bmp, including the 116px
    //     floor. The face never vanishes on any real skin.
    //   * Every OTHER sprite (title bars, thumb, ON/AUTO) lives in the canonical
    //     275x315 sheet's lower rows and is kept inside that modal sheet, so it
    //     renders correctly on the ~87% canonical majority. On a truncated sheet
    //     those rows are out of bounds, so `SpriteCutter` drops exactly those
    //     sprites (the face still renders) — the same graceful degradation the
    //     posbar thumb gets on a 248-wide minority sheet. We deliberately do NOT
    //     chase the 116px floor by deleting the lower sprites, which would corrupt
    //     the canonical majority.
    // The fit floor used by the fit test is therefore the canonical 275x315 (the
    // sheet where every declared sprite genuinely lives), with a SEPARATE pinned
    // assertion that the background fits the absolute-smallest 275x116 so the EQ
    // face can never overrun even the shortest real sheet.
    //
    // Layout convention (top-left origin), clean-room from the public EQ layout:
    //   * y = 0,   275x116 : the EQ window background / face (drawn whole).
    //   * y = 134, 275x14  : title bar, active (focused).
    //   * y = 149, 275x14  : title bar, inactive.
    //   * the slider THUMB is a small ~14x11 knob: normal at (0,164), pressed just
    //     below at (0,176). ONE thumb graphic is shared by the preamp slider and
    //     all ten band sliders (they are identical knobs in the format).
    //   * the ON button (EQ enable) and AUTO button (auto-preset) are small
    //     toggle graphics in the same control band: each has an OFF and an ON
    //     state. Public layout packs them near the upper-left of the EQ face's
    //     control row; their off/on pairs sit in the (10,119) / (128,119) bands.
    //
    // DEFERRED (documented, not modelled here):
    //   * eq_ex.bmp — the EQ windowshade (rolled-up title-bar-only) variant. Its
    //     own sheet; not keyed in `equalizerWindow`. A later increment.
    //   * the colored band-graph LINE gradient (the 1px-wide vertical color ramp
    //     the curve is drawn with) and the PRESET/TEXT micro-region: the public
    //     spec under-pins their exact packing, and neither is needed to composite
    //     the static EQ window (face + chrome + thumbs + ON/AUTO) in the next
    //     increment. Left to a later pass, exactly as the playlist micro-buttons
    //     were.

    private static let equalizerFace: [SpriteRect] = [
        // --- Window background / EQ face (drawn whole), y = 0 ---
        // Pinned to 275x116 so it fits even the 116px-floor truncated sheets.
        SpriteRect(name: "background", x: 0, y: 0, width: 275, height: 116),

        // --- Title bar, active (y = 134) and inactive (y = 149), 275x14 ---
        SpriteRect(name: "titleBarActive",   x: 0, y: 134, width: 275, height: 14),
        SpriteRect(name: "titleBarInactive", x: 0, y: 149, width: 275, height: 14),

        // --- Shared slider thumb (preamp + 10 bands), ~14x11 ---
        // Normal then pressed, stacked. provisional — tune at render.
        SpriteRect(name: "sliderThumb",        x: 0, y: 164, width: 14, height: 11),
        SpriteRect(name: "sliderThumbPressed", x: 0, y: 176, width: 14, height: 11),

        // --- ON button (EQ enable): off + on ---
        // The off-states group at the left of the control band (y = 119); the
        // on-states group to their right. Packed so no two button rects overlap
        // in the sheet. provisional — tune at render.
        SpriteRect(name: "onButtonOff", x: 10,  y: 119, width: 25, height: 12),
        SpriteRect(name: "onButtonOn",  x: 128, y: 119, width: 25, height: 12),

        // --- AUTO button (auto-preset): off + on ---
        // provisional — tune at render
        SpriteRect(name: "autoButtonOff", x: 36,  y: 119, width: 32, height: 12),
        SpriteRect(name: "autoButtonOn",  x: 154, y: 119, width: 32, height: 12)
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
    // Canonical sheet is 307x10: a 248-wide seek track at x=0, then two 29-wide
    // slider-thumb sub-bitmaps — normal at x=248, pressed at x=278 — all 10px
    // tall (248 + 29 + 29 = 306, so the rects occupy x 0..306 on a 307-wide,
    // 10-tall sheet). These coordinates are correct and in-bounds on the modal
    // real sheet (307x10, ~96.5% of skins) and MUST NOT be shrunk: the dynamic
    // thumb genuinely lives at x=248/278, so clamping it would corrupt the
    // canonical skins.
    //
    // Two real-sheet minorities exist and are deliberately NOT chased by changing
    // these rects: (1) a few skins ship a 248-wide posbar — on those the `track`
    // still fits (right edge 248) and only the two thumb sub-bitmaps fall out of
    // bounds, so the static seek-bar background still renders and only the
    // dynamic thumb is missing; (2) a few skins ship a SHORT strip (2-9px tall)
    // that intentionally omits the thumb — those legitimately trade away the
    // slider thumb. Pinning the canonical 307x10 here keeps the modal majority
    // correct rather than corrupting them to chase those minorities.

    private static let positionBar: [SpriteRect] = [
        SpriteRect(name: "track",        x: 0,   y: 0, width: 248, height: 10),
        SpriteRect(name: "thumb",        x: 248, y: 0, width: 29,  height: 10),
        SpriteRect(name: "thumbPressed", x: 278, y: 0, width: 29,  height: 10)
    ]

    // MARK: - volume.bmp (volume slider)
    //
    // 28 stacked position frames (one per level), each 68 wide and 15 tall,
    // stacked from y=0. The slider thumb is baked into each frame, so there is no
    // separate thumb sprite. 28 * 15 = 420 is the nominal content height, and the
    // most common real sheet is taller still (433px). But a meaningful share of
    // real skins ship the sheet TRIMMED a pixel or two short (418/419px), and
    // there a 420-bottom last frame (level27, y=405..420) overruns the sheet —
    // `SpriteCutter` then drops it, and because it drops only the offending rect
    // the whole 28-frame set is left incomplete. To keep every level present on
    // those trimmed sheets, the last frame's bottom is capped at 418 (so
    // declaredMaxBottom = 418, in-bounds on the 418/419px sheets); level27 is the
    // highest-volume frame, so cropping its last rows is the least-visible trim.

    private static let volume: [SpriteRect] =
        sliderBackgrounds(count: 28, width: 68, height: 15, maxBottom: 418)

    // MARK: - balance.bmp (balance slider)
    //
    // Same vertical shape as the volume sheet — 28 stacked position frames from
    // y=0, each 15 tall, with the thumb baked in (no separate thumb sprite) —
    // but the balance frame is NARROWER than volume's: 47 wide, not 68. The
    // balance knob graphic only occupies the left portion of the strip, so the
    // canonical sheet is authored 47 wide. A 47-wide frame is in-bounds on both
    // 47-wide and 68-wide balance sheets; a 68-wide frame would overrun the many
    // skins that ship balance at 47px.
    //
    // The vertical extent shares volume's exposure: 28 * 15 = 420 is nominal, but
    // a share of real skins ship balance TRIMMED to 418/419px, where a 420-bottom
    // last frame overruns and `SpriteCutter` drops it (leaving the set
    // incomplete). The last frame's bottom is therefore capped at 418 (so
    // declaredMaxBottom = 418), matching the volume fix.

    private static let balance: [SpriteRect] =
        sliderBackgrounds(count: 28, width: 47, height: 15, maxBottom: 418)

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
    ///
    /// `maxBottom`, when supplied, caps the bottom edge of the LAST frame so the
    /// stack never overruns a sheet of that pixel height. The earlier frames are
    /// unaffected (they end well above the cap); only the final frame is cropped
    /// to `maxBottom - lastFrameTop` rows. This keeps all `count` frames present
    /// on real sheets that ship a few pixels short of the nominal `count*height`,
    /// where dropping the overrunning last frame would otherwise make
    /// `SpriteCutter` reject it (the dependent control would lose that level).
    private static func sliderBackgrounds(
        count: Int, width: Int, height: Int, maxBottom: Int? = nil
    ) -> [SpriteRect] {
        (0..<count).map { level in
            let top = level * height
            var frameHeight = height
            if let maxBottom, level == count - 1, top + height > maxBottom {
                frameHeight = maxBottom - top
            }
            return SpriteRect(name: "level\(level)", x: 0, y: top, width: width, height: frameHeight)
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
