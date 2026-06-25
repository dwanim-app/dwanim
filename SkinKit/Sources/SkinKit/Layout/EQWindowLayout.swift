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
    // the current band gains). The compositor draws the curve into this rect;
    // pixels outside it are left untouched. The colored line gradient itself
    // (its per-row colors) is DEFERRED in `SpriteCoordinates` — only the area is
    // pinned here.

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
