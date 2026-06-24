import Foundation

// MARK: - MainWindowLayout
//
// Clean-room layout table for the classic 275x116 main player window. For each
// static control it records WHERE the control draws on the window and WHICH
// sprite (sheet + name) supplies its default/static state. These on-window
// destination coordinates are factual descriptions of the public classic `.wsz`
// skin format layout — the fixed pixel slots the format mandates for each
// control — and are not transcribed from any proprietary product source.
//
// Source: the public classic `.wsz` skin format layout.
//
// Convention: top-left origin, x rightward / y downward, pixels. Destination
// coordinates are positions on the 275x116 main window. The referenced sprite's
// pixel size comes from `SpriteCoordinates.mainWindow`; this table only fixes
// the (x, y) where that sprite's top-left lands.
//
// DATA ONLY: this file is pure `Foundation` and carries no rendering logic. The
// compositor that consumes it lives in the platform shell.

/// Static layout of the classic 275x116 main player window: where each default
/// control sprite is composited over `main.bmp`.
public enum MainWindowLayout {

    /// Window dimensions, in pixels. The classic main window is a fixed size.
    public static let windowWidth = 275
    public static let windowHeight = 116

    // MARK: - Dynamic-content origins
    //
    // Top-left destinations for the dynamic text/number overlays the player
    // patches onto the composed base buffer (the song title and the time
    // display). These are NOT static-sprite elements, so they live here as
    // standalone origins rather than in `elements`. Clean-room from the public
    // format layout.

    /// Top-left of the song-title text region (the scrolling track name strip,
    /// upper area of the window).
    // provisional — tune at render
    public static let titleTextOrigin = (x: 111, y: 27)

    /// Width of the song-title display region, in pixels. The title is clipped
    /// to this width so a long track name cannot bleed past the strip into the
    /// rest of the window (mono/stereo, the window edge). The classic title
    /// display is roughly ~150px wide.
    // provisional — tune at render
    public static let titleTextWidth = 150

    /// Top-left of the MM:SS time display (digits beside the title, upper-left).
    // provisional — tune at render
    public static let timeDisplayOrigin = (x: 48, y: 26)

    /// Top-left of the kbps (bitrate) number box — the small numeric field in the
    /// upper-middle row, below the title strip and left of the kHz box. Drawn from
    /// `numbers.bmp` digits, RIGHT-aligned in `kbpsDisplayDigits` cells.
    // provisional — tune at render
    public static let kbpsDisplayOrigin = (x: 111, y: 43)

    /// Number of digit cells in the kbps field. Classic kbps is a 3-digit box.
    // provisional — tune at render
    public static let kbpsDisplayDigits = 3

    /// Top-left of the kHz (sample-rate) number box — the small numeric field just
    /// right of the kbps box in the same upper-middle row. Drawn from
    /// `numbers.bmp` digits, RIGHT-aligned in `khzDisplayDigits` cells.
    // provisional — tune at render
    public static let khzDisplayOrigin = (x: 156, y: 43)

    /// Number of digit cells in the kHz field. Classic kHz is a 2-digit box
    /// (e.g. 44 for 44.1 kHz, 48 for 48 kHz).
    // provisional — tune at render
    public static let khzDisplayDigits = 2

    /// The classic main-window visualization (spectrum/oscilloscope) area: the
    /// rectangular region the player draws the live spectrum into, just below the
    /// title bar and to the left of the title display. `(x, y)` is the top-left
    /// corner; `width`/`height` the region size, in window pixels.
    ///
    /// Clean-room from the public classic `.wsz` format layout (the ~24,43,76,16
    /// vis region). A consumer (e.g. `SkinRender.SpectrumRenderer`) draws bars into
    /// this rect; pixels outside it are left untouched.
    // provisional — tune at render
    public static let visualizationFrame = (x: 24, y: 43, width: 76, height: 16)

    /// Static controls to composite over `main.bmp`, in draw order (back to
    /// front). The background itself is NOT in this list — the compositor draws
    /// `main.bmp`/`background` first, then overlays these.
    ///
    /// Each entry names the sprite's default/static state (released buttons,
    /// off toggles, stereo lit). Dynamic interactive states (pressed buttons,
    /// the live slider thumb position) are out of scope for this static table.
    public static let elements: [WindowElement] = [
        // MARK: Title bar (top strip, y = 0)
        //
        // The active title bar spans the full window width at the very top.
        WindowElement(sheet: "titlebar.bmp", sprite: "titleBarActive", x: 0, y: 0),

        // MARK: Mono / stereo indicator (stereo lit)
        //
        // The mono/stereo labels sit in the upper-right, just below the title
        // bar and to the right of the time display. Stereo is shown active.
        // provisional — tune at render
        WindowElement(sheet: "monoster.bmp", sprite: "monoActive",   x: 212, y: 41),
        // provisional — tune at render
        WindowElement(sheet: "monoster.bmp", sprite: "stereoActive", x: 239, y: 41),

        // MARK: Position / seek bar track
        //
        // The seek track runs across the lower-middle of the window. The live
        // thumb is dynamic and omitted from this static table.
        WindowElement(sheet: "posbar.bmp", sprite: "track", x: 16, y: 72),

        // MARK: Transport buttons (released state row)
        //
        // Five 23x18 buttons in a row along the bottom-left. Each button's left
        // edge is the previous edge + 23 (their footprint width). play and pause
        // are distinct sprites occupying adjacent slots.
        WindowElement(sheet: "cbuttons.bmp", sprite: "previous", x: 16,  y: 88),
        WindowElement(sheet: "cbuttons.bmp", sprite: "play",     x: 39,  y: 88),
        WindowElement(sheet: "cbuttons.bmp", sprite: "pause",    x: 62,  y: 88),
        WindowElement(sheet: "cbuttons.bmp", sprite: "stop",     x: 85,  y: 88),
        WindowElement(sheet: "cbuttons.bmp", sprite: "next",     x: 108, y: 88),

        // MARK: Shuffle + repeat toggles (off state)
        //
        // The two toggles sit at the bottom-right. shuffle (47 wide) is left of
        // repeat (28 wide). Both shown in their off state.
        // provisional — tune at render
        WindowElement(sheet: "shufrep.bmp", sprite: "shuffleOff", x: 164, y: 89),
        // provisional — tune at render
        WindowElement(sheet: "shufrep.bmp", sprite: "repeatOff",  x: 210, y: 89),

        // MARK: Volume slider background (default frame ~ full)
        //
        // The volume slider sits below the title bar on the left. We pick a high
        // level frame as the static default; the live thumb is baked into the
        // frame so no separate thumb sprite is needed.
        // provisional — tune at render
        WindowElement(sheet: "volume.bmp", sprite: "level27", x: 107, y: 57),

        // MARK: Balance slider background (default frame ~ center)
        //
        // The balance slider sits just right of the volume slider. We pick a
        // mid level frame (centered balance) as the static default.
        // provisional — tune at render
        WindowElement(sheet: "balance.bmp", sprite: "level13", x: 177, y: 57)

        // TODO: time / number display (numbers.bmp digits) and the scrolling
        // song title (text.bmp bitmap-font glyphs) are DEFERRED: they need
        // dynamic content plus the provisional text.bmp glyph map, so they are
        // not part of this static layout table.
    ]
}
