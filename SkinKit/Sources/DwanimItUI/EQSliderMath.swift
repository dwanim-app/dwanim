import PlayerCore

// MARK: - EQSliderMath

/// The pure, view-agnostic mapping between an equalizer gain in dB and a vertical
/// slider's `0...1` position fraction, plus the inverse from a cursor y inside a
/// track of a given height back to a gain. SwiftUI has no native vertical
/// `Slider`, so the default-skin EQ draws its own draggable band columns; this
/// enum is the seam that keeps the gain math out of the View (mirroring how
/// `SeekMath` keeps the seek math out of `ProgressTrack`), so it is unit-testable
/// in isolation without rendering anything.
///
/// ## Orientation
/// A band column reads like the classic EQ: **top = max gain (+12 dB), bottom =
/// min gain (−12 dB)**, centre = 0 dB (flat). So a position fraction of `1`
/// (top of the track) is `gainRange.upperBound` and `0` (bottom) is
/// `gainRange.lowerBound`. In SwiftUI, y grows DOWNWARD, so a cursor at y == 0
/// (the track top) is the MAX gain — `gain(forY:height:)` flips accordingly.
///
/// ## Contract (mirrors the `EQState`/`PlayerCore` setters)
/// - Every result is CLAMPED into `EQState.gainRange` (`−12...+12 dB`).
/// - A non-finite gain or a degenerate (zero / non-finite) track height is
///   handled defensively: `fraction(forGain:)` reads a non-finite gain as `0`
///   (centre); `gain(forY:height:)` reads a degenerate height as `0 dB`. The
///   View never feeds a NaN through to `PlayerCore`, and `PlayerCore`'s own
///   setters guard `isFinite` again as a backstop.
enum EQSliderMath {

    /// The `0...1` position fraction (0 = bottom / min gain, 1 = top / max gain)
    /// for a gain in dB. The gain is first clamped to `EQState.gainRange`; a
    /// non-finite gain reads as `0 dB` (centre, fraction `0.5`).
    static func fraction(forGain dB: Double) -> Double {
        let g = dB.isFinite ? clampGain(dB) : 0
        let lo = EQState.gainRange.lowerBound
        let hi = EQState.gainRange.upperBound
        let span = hi - lo
        guard span > 0 else { return 0.5 }
        return (g - lo) / span
    }

    /// The gain in dB for a cursor `y` inside a track `height` points tall, where
    /// y grows DOWNWARD (y == 0 is the track TOP = max gain). The y is clamped to
    /// `0...height`, mapped to a top-origin fraction, and converted to a gain in
    /// `EQState.gainRange`. A degenerate height (`<= 0` or non-finite) or a
    /// non-finite y reads as `0 dB` (flat) rather than dividing.
    static func gain(forY y: Double, height: Double) -> Double {
        guard height.isFinite, height > 0, y.isFinite else { return 0 }
        let clampedY = min(max(y, 0), height)
        // Flip: top (y == 0) is max gain, bottom (y == height) is min gain.
        let topFraction = 1 - (clampedY / height)
        return gain(forFraction: topFraction)
    }

    /// The gain in dB for a `0...1` position fraction (0 = bottom / min, 1 = top /
    /// max). The fraction is clamped to `0...1`, then mapped onto
    /// `EQState.gainRange`. Used by `gain(forY:height:)` and reusable directly.
    static func gain(forFraction fraction: Double) -> Double {
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0.5
        let lo = EQState.gainRange.lowerBound
        let hi = EQState.gainRange.upperBound
        return clampGain(lo + f * (hi - lo))
    }

    /// Clamp a (finite) dB into `EQState.gainRange`. Callers guard `isFinite`.
    private static func clampGain(_ dB: Double) -> Double {
        min(max(dB, EQState.gainRange.lowerBound), EQState.gainRange.upperBound)
    }
}
