import Foundation
import SkinKit

// MARK: - EQWindowComposer
//
// Pure RGBA8 compositor for the classic 275x116 equalizer (EQ) window face. Like
// `MainWindowComposer`, it needs NO graphics framework: compositing is just
// copying sprite pixels onto a copy of the background buffer at each control's
// (x, y), all in `DecodedBitmap`'s top-left-origin RGBA8 space (no vertical
// flip). Every blit goes through the shared `SkinCanvas.overlay`, which clips to
// bounds and skips size-inconsistent sprites, so missing/malformed control
// sprites are tolerated and no write ever lands out of range.
//
// MODULE DEPENDENCY NOTE: `compose` takes the EQ state as RAW values
// (`enabled`, `preamp`, `bands`) rather than the `PlayerCore.EQState` type,
// because `SkinRender` depends only on `SkinKit` — NOT on `PlayerCore`. Threading
// the state in as plain `Bool`/`Double` keeps the module graph clean (the caller
// in the platform shell, which already has `PlayerCore`, unpacks `EQState` into
// these arguments). The values follow the same contract `EQState` enforces: gains
// are dB, sanitised/clamped to `±12 dB` by `EQWindowLayout.thumbTopY`.
//
// The colored band-graph response CURVE is now drawn over
// `EQWindowLayout.graphFrame`: `EQResponseCurve` maps the ten band gains to a
// per-column polyline, and each column's curve pixel is tinted by the
// `graphLineColorRamp` sprite (indexed by the curve's height within the graph). On
// a truncated sheet that omits the ramp, the curve falls back to a single sane line
// color — it is never skipped and never crashes. All curve writes are clipped to
// the graph rectangle and go through a bounds-checked pixel setter.
//
// DEFERRED (documented, not drawn here):
//   * the PRESET / status text in `EQWindowLayout.presetDisplayOrigin` (drawn
//     from the bitmap font at a later increment);
//   * the AUTO on-state (no auto-preset flag is modelled yet — AUTO is drawn OFF);
//   * the `eq_ex.bmp` windowshade (rolled-up) variant.

public enum EQWindowComposer {

    // MARK: - Compose

    /// Composite the equalizer window into a single RGBA8 bitmap (275x116):
    /// start from a COPY of `eqmain.bmp/background`, overlay the slider thumb for
    /// the preamp and each of the ten bands at its column x and gain-derived y,
    /// then overlay the ON button (on/off per `enabled`) and the AUTO button
    /// (always OFF for now). Returns `nil` only if the background sprite is absent
    /// or malformed.
    ///
    /// - Parameters:
    ///   - skin: the loaded skin to pull `eqmain.bmp` sprites from.
    ///   - enabled: whether the equalizer is on (selects the ON button sprite).
    ///   - preamp: preamp gain in dB; placed on the preamp slider column.
    ///   - bands: per-band gains in dB. An array of any length is tolerated — only
    ///     the first ten entries are used, and a short array leaves the remaining
    ///     band thumbs unplaced (the background shows through), never trapping.
    ///   - active: reserved for the active/inactive title bar (the bare face does
    ///     not include the title strip); accepted for symmetry with the other
    ///     composers and forward use.
    public static func compose(
        _ skin: Skin,
        enabled: Bool,
        preamp: Double,
        bands: [Double],
        active: Bool = true
    ) -> DecodedBitmap? {
        guard let background = skin.sprite(sheet: "eqmain.bmp", name: "background") else {
            return nil
        }

        let width = background.width
        let height = background.height
        // `DecodedBitmap` does not enforce that its backing buffer holds exactly
        // `width * height * 4` bytes. An undersized background would make the blit
        // read/write out of range, so treat a malformed background as no usable
        // background (same guard class as `MainWindowComposer`).
        guard background.pixels.count == width * height * 4 else {
            return nil
        }

        // Start from a COPY of the background, then overlay each control through
        // the shared blit primitive. `overlay` clips to bounds and skips a missing
        // or size-inconsistent sprite, so every step below is fault tolerant.
        var canvas = DecodedBitmap(width: width, height: height, pixels: background.pixels)

        // (2) Slider thumbs: preamp column, then the ten band columns. One shared
        // thumb graphic; only the gain (→ y) and the column (x) differ. A missing
        // thumb sprite simply leaves the columns bare (background shows through).
        if let thumb = skin.sprite(sheet: "eqmain.bmp", name: "sliderThumb") {
            // Preamp.
            SkinCanvas.overlay(
                thumb,
                onto: &canvas,
                x: EQWindowLayout.preampSliderX,
                y: EQWindowLayout.thumbTopY(forGain: preamp)
            )
            // Ten bands: index into the layout's column table; tolerate an
            // off-length `bands` array by only placing the bands actually present.
            let columns = EQWindowLayout.bandSliderXs
            for index in 0..<min(columns.count, bands.count) {
                SkinCanvas.overlay(
                    thumb,
                    onto: &canvas,
                    x: columns[index],
                    y: EQWindowLayout.thumbTopY(forGain: bands[index])
                )
            }
        }

        // (3) ON button: on-state when the equalizer is enabled, off-state when
        // disabled. AUTO button: always the off-state for now (no auto-preset flag
        // is modelled). Both missing-sprite tolerant.
        let onSpriteName = enabled ? "onButtonOn" : "onButtonOff"
        if let onSprite = skin.sprite(sheet: "eqmain.bmp", name: onSpriteName) {
            SkinCanvas.overlay(
                onSprite,
                onto: &canvas,
                x: EQWindowLayout.onButtonOrigin.x,
                y: EQWindowLayout.onButtonOrigin.y
            )
        }
        if let autoSprite = skin.sprite(sheet: "eqmain.bmp", name: "autoButtonOff") {
            SkinCanvas.overlay(
                autoSprite,
                onto: &canvas,
                x: EQWindowLayout.autoButtonOrigin.x,
                y: EQWindowLayout.autoButtonOrigin.y
            )
        }

        // (4) Response CURVE: plot the band-response polyline across the graph area,
        // tinted by the graph color ramp. Drawn LAST so it sits over the face. The
        // ramp is optional — absent on truncated sheets — and the curve degrades to
        // a single line color rather than vanishing.
        drawResponseCurve(bands: bands, ramp: skin.sprite(sheet: "eqmain.bmp", name: "graphLineColorRamp"), onto: &canvas)

        return canvas
    }

    // MARK: - Response curve

    /// Fallback line color (RGBA) when the graph color ramp sprite is absent (a
    /// truncated sheet). A bright classic-EQ green so the curve is still visible.
    private static let fallbackLineColor: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)

    /// Plot the EQ response curve over `EQWindowLayout.graphFrame` onto `canvas`.
    /// For each x column in the graph, `EQResponseCurve` gives the curve's window-y;
    /// a 1px dot is written there (plus the pixel one row below, for a slightly
    /// thicker, more legible line), clipped to the graph rectangle. Each dot is
    /// colored by `ramp` indexed by the curve's row WITHIN the graph (top row → ramp
    /// row 0), or by `fallbackLineColor` when `ramp` is nil/malformed. Every write
    /// is bounds-checked, so nothing lands outside the graph or off the buffer.
    private static func drawResponseCurve(
        bands: [Double],
        ramp: DecodedBitmap?,
        onto canvas: inout DecodedBitmap
    ) {
        let frame = EQWindowLayout.graphFrame
        guard frame.width > 0, frame.height > 0 else { return }
        // The graph must lie within the buffer to draw anything (a 116-tall face
        // holds the y=17 graph; this also guards a future mis-tuned frame).
        guard frame.x >= 0, frame.y >= 0,
              frame.x + frame.width <= canvas.width,
              frame.y + frame.height <= canvas.height,
              canvas.pixels.count == canvas.width * canvas.height * 4
        else { return }

        // A usable ramp is exactly 1px wide (or wider — we read column 0) and at
        // least one row tall, with a size-consistent buffer. Otherwise fall back.
        let usableRamp: DecodedBitmap?
        if let ramp, ramp.width >= 1, ramp.height >= 1,
           ramp.pixels.count == ramp.width * ramp.height * 4 {
            usableRamp = ramp
        } else {
            usableRamp = nil
        }

        let topRow = frame.y
        let bottomRow = frame.y + frame.height - 1
        let ys = EQResponseCurve.yPositions(forBandGains: bands)

        var pixels = canvas.pixels
        // `ys` has exactly `frame.width` entries (one per column); iterate by the
        // smaller of the two for total safety against any future shape change.
        for column in 0..<Swift.min(ys.count, frame.width) {
            let x = frame.x + column
            let y = Swift.min(Swift.max(ys[column], topRow), bottomRow)

            let color = curveColor(forRow: y, top: topRow, bottom: bottomRow, ramp: usableRamp)
            setPixel(&pixels, width: canvas.width, x: x, y: y, color: color, frame: frame)
            // A second pixel one row down thickens the line; clipped to the graph.
            setPixel(&pixels, width: canvas.width, x: x, y: y + 1, color: color, frame: frame)
        }
        canvas = DecodedBitmap(width: canvas.width, height: canvas.height, pixels: pixels)
    }

    /// The curve color for a window `row`, from the color `ramp` indexed by the
    /// row's fraction within the graph (`top` → ramp row 0, `bottom` → the ramp's
    /// last row), reading the ramp's leftmost (x=0) column. Falls back to
    /// `fallbackLineColor` when `ramp` is nil.
    private static func curveColor(
        forRow row: Int,
        top: Int,
        bottom: Int,
        ramp: DecodedBitmap?
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        guard let ramp else { return fallbackLineColor }
        // Map the row's position in the graph onto a ramp row.
        let span = bottom - top
        let fraction = span > 0 ? Double(row - top) / Double(span) : 0
        let rampRow = Swift.min(
            Swift.max(Int((fraction * Double(ramp.height - 1)).rounded()), 0),
            ramp.height - 1
        )
        let index = (rampRow * ramp.width + 0) * 4
        // Defensive: the ramp buffer was size-checked by the caller, but re-guard.
        guard index + 3 < ramp.pixels.count else { return fallbackLineColor }
        return (ramp.pixels[index], ramp.pixels[index + 1], ramp.pixels[index + 2], ramp.pixels[index + 3])
    }

    /// Write one opaque pixel at `(x, y)` into `pixels`, but ONLY when it lies inside
    /// the graph `frame` AND inside the buffer. Out-of-graph or out-of-buffer writes
    /// are skipped, so the curve can never spill past the graph or trap.
    private static func setPixel(
        _ pixels: inout [UInt8],
        width: Int,
        x: Int,
        y: Int,
        color: (UInt8, UInt8, UInt8, UInt8),
        frame: (x: Int, y: Int, width: Int, height: Int)
    ) {
        // Clip to the graph rectangle first.
        guard x >= frame.x, x < frame.x + frame.width,
              y >= frame.y, y < frame.y + frame.height
        else { return }
        let index = (y * width + x) * 4
        guard index >= 0, index + 3 < pixels.count else { return }
        pixels[index] = color.0
        pixels[index + 1] = color.1
        pixels[index + 2] = color.2
        pixels[index + 3] = color.3
    }
}
