import Foundation

// MARK: - PresentationScale
//
// Pure math for the classic windows' PRESENTATION scale — the number of window
// POINTS one skin pixel occupies (e.g. 1.5 renders the 275x116 main window at
// 412.5 x 174 points). It needs NO graphics framework; the AppKit shell consumes
// the derived factor.
//
// WHY a fractional presentation scale works crisply on Retina: the composed skin
// bitmap must be upscaled by an INTEGER nearest-neighbor factor or the pixel art
// smears (a fractional resample duplicates some source rows/columns and not
// others). On a 2x-backing display, 1.5 POINTS per skin pixel is EXACTLY
// 3 DEVICE PIXELS per skin pixel — an integer ratio. So the bitmap is rendered
// once at an integer 3x with nearest-neighbor, and the view draws it into
// 1.5x-points bounds: bounds(points) * backingScaleFactor(2) == bitmap pixels,
// a 1:1 device-pixel copy with no resampling.
//
// `bitmapScale(forPresentationScale:)` is that derivation, in one tested place:
//   - an INTEGER presentation scale keeps bitmap == presentation (1 -> 1, 2 -> 2;
//     the harness's integer `--scale` path is bit-for-bit unchanged),
//   - a FRACTIONAL presentation scale doubles to the 2x-backing device factor
//     (1.5 -> 3), rounded to the nearest integer so the factor is always whole.
// A degenerate scale (non-finite, zero, negative) yields 1, matching the
// project's finite-guard convention (a sane default, never a trap).

public enum PresentationScale {

    /// The INTEGER nearest-neighbor factor to render the composed skin bitmap at
    /// for a given presentation `scale` (points per skin pixel). Integer scales
    /// map to themselves (bitmap == presentation, the historical behavior);
    /// fractional scales map to `round(scale * 2)` — the device-pixel factor on a
    /// 2x (Retina) backing, where the fractional point size is exactly integer in
    /// device pixels (1.5 -> 3). Non-finite / non-positive input yields 1.
    public static func bitmapScale(forPresentationScale scale: Double) -> Int {
        guard scale.isFinite, scale > 0 else { return 1 }
        if scale == scale.rounded() {
            return Int(scale)
        }
        return max(1, Int((scale * 2).rounded()))
    }
}
