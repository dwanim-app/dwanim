import Foundation
import SkinKit

// MARK: - SpectrumRenderer
//
// Pure spectrum-bar rendering for the classic main window's visualization area.
// It needs NO graphics framework and NO audio framework: drawing a frame of bar
// levels is just writing RGBA8 pixels into a base buffer within a rect, clipped
// to the rect and to the base bounds. The DSP that produces the levels (the
// `SpectrumAnalyzer`) and the audio tap that feeds it live OUTSIDE this module
// (in the harness/shell); this renderer is the drawing half of the seam only.
//
// Bars fill from the BOTTOM of the rect UPWARD (a level of 1.0 reaches the top
// row), matching the classic spectrum display. Color comes from the skin's
// `viscolor.txt` palette used as a vertical gradient — a filled pixel's height
// fraction selects a palette entry so taller pixels are "hotter". When the skin
// carries no palette, a single sane fallback color is used so the visualizer is
// still visible.
//
// All writes are direct RGBA8 pixel writes (this is per-pixel, not a sprite
// blit, so it does not go through `SkinCanvas.overlay`); every write is guarded
// to stay inside both the rect and the base bounds, and a size-inconsistent base
// is skipped — the same fault-tolerance the other renderers rely on. Pixels
// outside the bars are left untouched so the skin background shows through.

public enum SpectrumRenderer {

    // MARK: - Tuning
    //
    // provisional — tune at render. A 1px inter-bar gap keeps adjacent bars
    // visually distinct; it is dropped automatically when a bar slot is only 1px
    // wide (so narrow vis areas still draw solid bars rather than nothing).

    /// Inter-bar gap, in pixels, reserved on the right of each bar's slot.
    private static let barGap = 1

    /// Fallback bar color when the skin's palette is empty: a classic green, a
    /// sane visible color that is not the typical dark skin background.
    private static let fallbackColor = RGBColor(r: 0, g: 255, b: 0)

    // MARK: - Draw

    /// Draw `levels` (each `0...1`) as vertical bars into `base` within the rect
    /// `(x, y, width, height)` (top-left origin), colored from `palette` (the
    /// skin's `visColors`).
    ///
    /// Layout: `levels.count` bars are laid evenly across `width`. Each bar gets a
    /// slot of `width / levels.count` pixels and fills all but the rightmost
    /// `barGap` pixels of its slot (the gap is dropped when a slot is 1px wide).
    /// A bar's filled pixel height is `round(clamp(level, 0, 1) * height)`, drawn
    /// from the BOTTOM of the rect upward.
    ///
    /// Color: the filled pixels of a bar form a vertical gradient over `palette` —
    /// a pixel at height fraction `f` (0 at the rect bottom, 1 at the top) uses
    /// palette entry `clamp(round(f * (count - 1)), 0, count - 1)`, so taller =
    /// later palette entry = "hotter". An empty `palette` uses a single fallback
    /// color.
    ///
    /// Clipping: writes are clipped to the rect AND to `base`'s bounds; nothing is
    /// written out of range. A size-inconsistent `base` (buffer != width*height*4)
    /// is skipped. Pixels outside the bars are left untouched.
    public static func draw(
        _ levels: [Float],
        into base: inout DecodedBitmap,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        palette: [RGBColor]
    ) {
        // Size-consistency guard: a malformed buffer would trap the pixel writes.
        guard base.pixels.count == base.width * base.height * 4 else { return }
        guard !levels.isEmpty, width > 0, height > 0 else { return }

        let barCount = levels.count
        let slotWidth = width / barCount
        guard slotWidth > 0 else { return } // more bars than pixels: nothing fits

        // Drop the gap when a slot is only 1px wide so a narrow vis area still
        // draws solid bars rather than all-gap (zero-width) bars.
        let fillWidth = slotWidth > barGap ? slotWidth - barGap : slotWidth

        var pixels = base.pixels
        let baseWidth = base.width
        let baseHeight = base.height

        for barIndex in 0..<barCount {
            // NaN would survive min/max and trap the Int() conversion below, so
            // treat a NaN level as silent. (±inf clamp correctly to 1 / 0.)
            let raw = levels[barIndex]
            let level = raw.isNaN ? 0 : min(max(raw, 0), 1)
            // Filled height in pixels, bottom-up; rounds so 0.5 fills ~half.
            let filledHeight = Int((Double(level) * Double(height)).rounded())
            guard filledHeight > 0 else { continue }

            let barLeft = x + barIndex * slotWidth

            for column in 0..<fillWidth {
                let px = barLeft + column
                guard px >= 0, px < baseWidth else { continue }

                // Fill from the rect bottom (y + height - 1) upward by filledHeight.
                for row in 0..<filledHeight {
                    let py = y + height - 1 - row
                    guard py >= 0, py < baseHeight else { continue }

                    // Height fraction: 0 at the bottom filled pixel, →1 at the top.
                    // Guard the single-pixel-tall case (height==1) against /0.
                    let fraction = height > 1 ? Double(row) / Double(height - 1) : 0
                    let color = colorForFraction(fraction, palette: palette)

                    let offset = (py * baseWidth + px) * 4
                    pixels[offset] = color.r
                    pixels[offset + 1] = color.g
                    pixels[offset + 2] = color.b
                    pixels[offset + 3] = 0xFF // opaque, matching the skin composite
                }
            }
        }

        base = DecodedBitmap(width: baseWidth, height: baseHeight, pixels: pixels)
    }

    // MARK: - Palette gradient

    /// The bar color for a filled pixel at height `fraction` (0 = bottom, 1 = top)
    /// over `palette`: a vertical gradient that selects a later palette entry as
    /// the fraction rises. An empty palette returns the single fallback color.
    private static func colorForFraction(_ fraction: Double, palette: [RGBColor]) -> RGBColor {
        guard let last = palette.indices.last else { return fallbackColor }
        let clampedFraction = min(max(fraction, 0), 1)
        let index = Int((clampedFraction * Double(last)).rounded())
        return palette[min(max(index, 0), last)]
    }
}
