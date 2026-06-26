import Foundation

// MARK: - SeekMath

/// Pure, UI-agnostic mapping between a horizontal seek-bar gesture and playback
/// time. Kept out of any SwiftUI view so it is unit-testable in isolation and so
/// the same guards apply to every caller (the default-skin bar, and any future
/// seek control).
///
/// Two complementary directions:
/// - `time(forFraction:duration:)` — a gesture fraction in `0...1` -> the absolute
///   seek time to hand to `PlayerCore.seek(to:)`.
/// - `fraction(currentTime:duration:)` — the live clock -> the `0...1` display
///   fraction the bar fills to when *not* scrubbing.
///
/// Every entry point is fully guarded: a non-finite or non-positive `duration`
/// means "not seekable" (the time mapping returns `nil`; the display fraction
/// returns `0`), the fraction is always clamped to `0...1`, and a non-finite
/// `currentTime` reads as `0`. The functions never produce `NaN`/`±inf`.
public enum SeekMath {

    /// Map a horizontal gesture fraction to an absolute seek time in seconds.
    ///
    /// - Parameters:
    ///   - fraction: The touch position along the bar as a fraction of its width.
    ///     Clamped to `0...1`, so values from a drag that runs past either edge
    ///     still map to the endpoints rather than off the track.
    ///   - duration: The current track length in seconds.
    /// - Returns: The clamped seek time (`fraction * duration`), or `nil` when the
    ///   source is not seekable — `duration` is not finite or is `<= 0` (nothing
    ///   loaded, or a non-seekable source). A `nil` result means "do not seek".
    ///
    /// Guarantees: with a seekable `duration`, the result is always finite and in
    /// `0...duration`. A non-finite `fraction` is treated as `0` (it fails the
    /// finite check before clamping), so it can never leak `NaN` into a seek.
    public static func time(forFraction fraction: Double, duration: TimeInterval) -> TimeInterval? {
        guard duration.isFinite, duration > 0 else { return nil }
        let safeFraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return safeFraction * duration
    }

    /// Map a horizontal gesture x-position + bar width to an absolute seek time.
    ///
    /// A convenience over `time(forFraction:duration:)` for callers that have a
    /// touch x and the bar width (e.g. a `DragGesture` inside a `GeometryReader`).
    /// A non-positive or non-finite `width` is treated as a fraction of `0`.
    public static func time(forX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval? {
        let fraction: Double
        if width.isFinite, width > 0, x.isFinite {
            fraction = Double(x / width)
        } else {
            fraction = 0
        }
        return time(forFraction: fraction, duration: duration)
    }

    /// Map the live clock to the `0...1` display fraction the bar fills to.
    ///
    /// - Parameters:
    ///   - currentTime: The live playback position in seconds. A non-finite value
    ///     reads as `0`.
    ///   - duration: The current track length in seconds.
    /// - Returns: `currentTime / duration` clamped to `0...1`, or `0` when the
    ///   duration is unknown/zero/non-finite (so the bar reads empty rather than
    ///   dividing by zero). The result is always finite and in `0...1`.
    public static func fraction(currentTime: TimeInterval, duration: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        let safeTime = currentTime.isFinite ? currentTime : 0
        return min(max(safeTime / duration, 0), 1)
    }
}
