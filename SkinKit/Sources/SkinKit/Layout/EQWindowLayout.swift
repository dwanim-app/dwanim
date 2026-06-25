import Foundation

// MARK: - EQWindowLayout
//
// Clean-room layout table for the classic 275x116 equalizer (EQ) window. It
// records the on-window positions of the interactive controls the EQ-window
// compositor (next increment) will place over the EQ face: the preamp slider,
// the ten band sliders, the ON / AUTO toggle buttons, the response-curve graph
// area, and the preset-display origin. These destination coordinates are
// factual descriptions of the public classic `.wsz` EQ-window layout — the fixed
// pixel slots the format mandates — and are not transcribed from any proprietary
// product source.
//
// Source: the public classic `.wsz` skin format EQ-window layout.
//
// Convention: top-left origin, x rightward / y downward, pixels. Positions are
// on the 275x116 EQ window. The slider thumb/button sprite sizes come from
// `SpriteCoordinates.equalizerWindow`; this table fixes WHERE on the window each
// control's track / origin lands.
//
// DATA ONLY: pure `Foundation`, no rendering logic. The compositor that consumes
// it lives in the platform shell. All positions are marked provisional — they
// are tuned against the real face at render time, exactly like
// `MainWindowLayout`'s provisional slots.

/// Static layout of the classic 275x116 equalizer window: where each slider
/// track, toggle button, the graph area, and the preset display sit over the EQ
/// face (`eqmain.bmp/background`).
public enum EQWindowLayout {

    /// Window dimensions, in pixels. The classic EQ window is a fixed size, the
    /// same 275x116 footprint as the main window.
    public static let windowWidth = 275
    public static let windowHeight = 116

    // MARK: - Equalizer slider geometry
    //
    // Eleven vertical sliders sit in a row across the lower half of the EQ face:
    // the PREAMP slider on the left, then the TEN frequency-band sliders. Every
    // slider shares the same vertical TRACK — the thumb travels along the same
    // y-range — and the same thumb graphic (`sliderThumb`). Only the x column
    // differs between sliders.

    /// Top of the slider track travel (the y of the thumb's top-left when the
    /// thumb is at the TOP / maximum-gain end of its range).
    // provisional — tune at render
    public static let sliderTrackTop = 38

    /// Bottom of the slider track travel (the y of the thumb's top-left when the
    /// thumb is at the BOTTOM / minimum-gain end). The thumb's full vertical
    /// travel is `sliderTrackTop ... sliderTrackBottom`; the centre (0 dB)
    /// position is their midpoint.
    // provisional — tune at render
    public static let sliderTrackBottom = 75

    /// The x column (thumb top-left x) of the PREAMP slider, left of the band
    /// sliders.
    // provisional — tune at render
    public static let preampSliderX = 21

    /// The x columns (thumb top-left x) of the TEN frequency-band sliders, left
    /// to right (low to high frequency). They are evenly spaced across the right
    /// portion of the face; each is `bandSliderSpacing` apart starting at
    /// `firstBandSliderX`.
    // provisional — tune at render
    public static let firstBandSliderX = 78
    /// Horizontal spacing between adjacent band-slider columns, in pixels.
    // provisional — tune at render
    public static let bandSliderSpacing = 18

    /// Convenience: the ten band-slider x columns, derived from
    /// `firstBandSliderX` + n * `bandSliderSpacing`.
    public static let bandSliderXs: [Int] =
        (0..<10).map { firstBandSliderX + $0 * bandSliderSpacing }

    /// Vertical centre of the slider track (the thumb top-left y for the 0 dB
    /// flat position). Handy for the compositor's default placement.
    public static var sliderTrackCenter: Int {
        (sliderTrackTop + sliderTrackBottom) / 2
    }

    // MARK: - Column -> which slider
    //
    // Which of the eleven sliders (the preamp or one of the ten bands) a click /
    // drag at a skin-space x belongs to. Used by the interactive drag to route a
    // gesture to the right gain. Pure column arithmetic — no y component, since
    // every slider shares the same track.

    /// Identifies a single EQ slider: the preamp, or one of the ten frequency
    /// bands by index `0..<10` (low to high frequency).
    public enum EQSlider: Equatable, Sendable {
        case preamp
        case band(Int)
    }

    /// The slider whose DRAWN THUMB is nearest the skin-space `x`, or `nil` when
    /// `x` is farther than the hit half-width from EVERY thumb. The compositor
    /// (`EQWindowComposer`) blits each thumb with its TOP-LEFT x AT the slider's
    /// column (`preampSliderX` / `bandSliderXs`), so the VISIBLE thumb spans
    /// `[columnX, columnX + thumbWidth)` and its DRAWN CENTRE is `columnX +
    /// thumbWidth/2`. This routine compares `x` against each thumb's DRAWN CENTRE
    /// (not its top-left column), so the hit region is centred on the visible thumb
    /// — clicking anywhere over the thumb, including its right half, grabs it. This
    /// mirrors the Y-axis centre compensation the drag uses (`skinY -
    /// thumbHeight/2`). A click within `hitHalfWidth` of a centre counts as that
    /// slider (so a near-miss still grabs it). The half-width is the thumb's own
    /// half-width but never more than half the inter-column spacing, so
    /// neighbouring band thumbs never both claim the same x — the nearer one wins.
    public static func slider(atSkinX x: Int) -> EQSlider? {
        // Hit half-width: cover the thumb body, but never reach past the midpoint
        // to the next thumb (bands are `bandSliderSpacing` apart).
        let half = Swift.min(thumbWidth / 2, bandSliderSpacing / 2)
        let drawnCentreOffset = thumbWidth / 2

        // Find the thumb whose DRAWN CENTRE is nearest `x` among preamp + the ten
        // bands; reject if it is beyond the hit half-width.
        var best: (slider: EQSlider, distance: Int)?
        func consider(_ slider: EQSlider, columnX: Int) {
            // Compare against the thumb's DRAWN CENTRE (top-left column + half the
            // thumb width), matching the composer's top-left blit.
            let centreX = columnX + drawnCentreOffset
            let distance = abs(x - centreX)
            if best == nil || distance < best!.distance {
                best = (slider, distance)
            }
        }

        consider(.preamp, columnX: preampSliderX)
        for (index, columnX) in bandSliderXs.enumerated() {
            consider(.band(index), columnX: columnX)
        }

        guard let best, best.distance <= half else { return nil }
        return best.slider
    }

    /// Height of the shared slider thumb knob, in pixels, read from the EQ sprite
    /// table (`eqmain.bmp/sliderThumb`). The thumb travel and the gain→y mapping
    /// account for this so the thumb body never spills past the track ends.
    /// Falls back to the canonical 11px if the sprite is ever absent from the
    /// table, keeping `thumbTopY` total and pure.
    public static var thumbHeight: Int {
        SpriteCoordinates.equalizerWindow["eqmain.bmp"]?
            .first { $0.name == "sliderThumb" }?
            .height ?? 11
    }

    /// Width of the shared slider thumb knob, in pixels, read from the same EQ
    /// sprite (`eqmain.bmp/sliderThumb`). Used to size the click hit-width when
    /// resolving which slider column a skin-space x lands on. Falls back to the
    /// canonical 14px if the sprite is absent, keeping `slider(atSkinX:)` total.
    public static var thumbWidth: Int {
        SpriteCoordinates.equalizerWindow["eqmain.bmp"]?
            .first { $0.name == "sliderThumb" }?
            .width ?? 14
    }

    // MARK: - Gain -> thumb position
    //
    // The pure mapping the EQ compositor uses to turn a band's dB gain into the
    // thumb's top-left y. It is linear and CLAMPED: +12 dB pins the thumb at the
    // TOP of the track (`sliderTrackTop`), -12 dB pins the thumb so its 11px body
    // rests on the BOTTOM (`sliderTrackBottom`), i.e. its top is
    // `sliderTrackBottom - thumbHeight`, and 0 dB centres the thumb on
    // `sliderTrackCenter`. Higher gain ⇒ smaller y (higher on screen).

    /// The thumb top-left **y** for a band/preamp `gain` in dB, clamped to the
    /// classic `-12...+12` range and to the track travel so the whole thumb body
    /// stays inside `[sliderTrackTop, sliderTrackBottom]`.
    ///
    /// - `+12` (or larger) ⇒ `sliderTrackTop` (thumb at the very top).
    /// - `-12` (or smaller) ⇒ `sliderTrackBottom - thumbHeight` (thumb body's
    ///   lower edge on the track bottom).
    /// - `0` ⇒ `sliderTrackCenter - thumbHeight/2` (thumb centred on the centre),
    ///   which is the midpoint of the travel.
    /// - A non-finite gain (`NaN`/`±inf`) is sanitised: `NaN` falls back to the
    ///   flat (centre) position; `±inf` clamps to the respective end — so the
    ///   result is always a valid in-track coordinate, never a garbage value.
    public static func thumbTopY(forGain gain: Double) -> Int {
        // Travel ends for the thumb's TOP-LEFT y. topY corresponds to +12 dB,
        // bottomY to -12 dB; the thumb body height keeps the knob inside the track.
        let topY = sliderTrackTop
        let bottomY = sliderTrackBottom - thumbHeight

        // NaN cannot be clamped (min/max with NaN is NaN), so map it to flat (0 dB).
        let clampedGain: Double = gain.isNaN
            ? 0
            : Swift.min(Swift.max(gain, gainMinDB), gainMaxDB)

        // Linear interpolate: +12 -> topY, -12 -> bottomY. fraction in 0...1 where
        // 0 == max boost (top), 1 == max cut (bottom).
        let fraction = (gainMaxDB - clampedGain) / (gainMaxDB - gainMinDB)
        let y = Double(topY) + fraction * Double(bottomY - topY)

        // Round to the nearest pixel, then clamp to the travel for total safety.
        let rounded = Int(y.rounded())
        return Swift.min(Swift.max(rounded, topY), bottomY)
    }

    // MARK: - Thumb position -> gain (inverse)
    //
    // The exact inverse of `thumbTopY`, used by the interactive drag: turn a
    // thumb-top y (where the cursor put the thumb, in skin space) back into a dB
    // gain. The track top (`sliderTrackTop`) maps to +12 dB, the track bottom
    // (`sliderTrackBottom - thumbHeight`) to -12 dB, linear and clamped between.
    // Higher on screen (smaller y) ⇒ more boost.

    /// The band/preamp `gain` in dB for a thumb top-left **y**, the inverse of
    /// `thumbTopY(forGain:)`. The y is clamped to the thumb-top travel
    /// `[sliderTrackTop, sliderTrackBottom - thumbHeight]` first, so the result is
    /// always inside `-12...+12 dB`:
    ///
    /// - `sliderTrackTop` (or above) ⇒ `+12` (max boost).
    /// - `sliderTrackBottom - thumbHeight` (or below) ⇒ `-12` (max cut).
    /// - the travel midpoint ⇒ `0` (flat).
    ///
    /// Within rounding, `thumbTopY(forGain: thumbGain(forThumbTopY: y)) == y` for
    /// every in-track y, and `thumbGain(forThumbTopY: thumbTopY(forGain: g)) ≈ g`.
    public static func thumbGain(forThumbTopY y: Int) -> Double {
        let topY = sliderTrackTop
        let bottomY = sliderTrackBottom - thumbHeight

        // A degenerate (zero-length) travel cannot map a y to a gain; report flat
        // rather than dividing by zero. The layout always has top < bottom, so
        // this only guards a future mis-tuning.
        guard bottomY > topY else { return 0 }

        // Clamp y into the travel, then invert the linear map: fraction 0 at the
        // top (max boost) → +12, fraction 1 at the bottom (max cut) → -12.
        let clampedY = Swift.min(Swift.max(y, topY), bottomY)
        let fraction = Double(clampedY - topY) / Double(bottomY - topY)
        return gainMaxDB - fraction * (gainMaxDB - gainMinDB)
    }

    /// The classic graphic-equalizer per-gain dB range the slider travel maps,
    /// mirrored from `EQState.gainRange` (kept as plain literals here so the pure
    /// layout table needs no `PlayerCore` dependency).
    public static let gainMaxDB = 12.0
    public static let gainMinDB = -12.0

    // MARK: - Toggle buttons (ON / AUTO)
    //
    // Two small toggle buttons in the upper-left of the EQ face: ON enables the
    // equalizer, AUTO toggles auto-preset. Each has off/on sprites in
    // `eqmain.bmp` (`onButtonOff`/`onButtonOn`, `autoButtonOff`/`autoButtonOn`).

    /// Top-left destination of the ON button on the window. The ON sprite is 25px
    /// wide, so its right edge is at x = 39.
    // provisional — tune at render
    public static let onButtonOrigin = (x: 14, y: 18)

    /// Top-left destination of the AUTO button on the window, placed just right of
    /// the ON button's footprint (ON right edge = 39) so the two do not overlap.
    // provisional — tune at render
    public static let autoButtonOrigin = (x: 40, y: 18)

    // MARK: - Response-curve graph area
    //
    // The rectangular region in the upper-right of the EQ face where the
    // equalizer response curve / band-graph is drawn (the colored line plotting
    // the current band gains). The compositor (`EQWindowComposer`) maps the band
    // gains to a per-column polyline (`EQResponseCurve`) and plots it into this
    // rect, tinted by the `graphLineColorRamp` sprite; pixels outside the rect are
    // left untouched. Both the curve helper and the line color ramp are now
    // implemented — only this area rectangle is pinned here.

    /// The graph/curve area: `(x, y)` top-left corner; `width`/`height` the
    /// region size, in window pixels.
    // provisional — tune at render
    public static let graphFrame = (x: 86, y: 17, width: 113, height: 19)

    // MARK: - Preset display origin
    //
    // Top-left of the small preset-name / status text region. The actual glyphs
    // come from the bitmap font (text.bmp) at render time; this only fixes where
    // that text begins on the window.

    /// Top-left of the preset display text region.
    // provisional — tune at render
    public static let presetDisplayOrigin = (x: 217, y: 18)
}
