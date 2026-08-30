import AppKit
import CoreGraphics
import CoreText
import Foundation
import SkinKit
import SkinRender

// The classic MAIN-WINDOW title marquee's PLATFORM-TEXT fallback (one primary
// type per file, §12). The authentic 5x6 `text.bmp` bitmap font (drawn by
// `SkinRender.BitmapText`) covers only Latin / Nordic / digits / a fixed
// punctuation set, so a CJK / kana / Hangul title blanks under it. When
// `BitmapText.canRender` reports a title is NOT bitmap-renderable, the interactive
// controller SKIPS the bitmap marquee for that title and draws the WHOLE title
// here via CoreText instead — with the SAME scroll cadence as the bitmap marquee,
// so the two share one scroll-offset source and never fight.
//
// This reuses the classic playlist's CoreText pattern (`PlaylistTextStyle` for
// font + color resolution, and a `scaledFlippedRect`-style flip into the view's
// bottom-left point space at the presentation scale) so the two text surfaces
// cannot drift.

// MARK: - Main-window CoreText title marquee (bitmap-font fallback)

/// The CoreText fallback marquee for the classic main-window title strip. Pure
/// drawing + measurement; it owns NO scroll state — the interactive controller
/// drives the offset (the same offset the bitmap marquee uses), so there is one
/// coherent scroll source and no competing timer.
enum MainTitleMarquee {

    // MARK: Region (skin space, top-left origin)

    /// Left edge of the title strip — the SAME region the bitmap marquee draws in.
    private static var regionX: Int { MainWindowLayout.titleTextOrigin.x }
    /// Width of the title strip — identical to the bitmap marquee's clip width, so
    /// the overflow decision matches.
    private static var regionWidth: Int { MainWindowLayout.titleTextWidth }

    /// The vertical clip band, centered on the bitmap glyph band so the CoreText
    /// line sits where the bitmap title would. The bitmap font draws with its top
    /// at `titleTextOrigin.y` (27) and is 6px tall, so its vertical center is at
    /// y=30; this band is centered on that and widened enough that the CoreText
    /// line's ascenders / descenders are not clipped. It stays clear of the
    /// mono/stereo indicators (y=41) and the kbps / vis row (y=43) below it.
    private static let bandTop = 23
    private static let bandHeight = 14

    /// Gap (skin px) appended after the title before it repeats in the marquee, so
    /// the loop reads as a gap rather than the title abutting itself — the CoreText
    /// analogue of the bitmap marquee's 3-cell (15px) separator.
    static let gapSkinPx = 16

    // MARK: Measurement

    /// The rendered width of `title` in SKIN pixels, measured with the SAME font
    /// the overlay draws (resolved at unscaled size). The controller's scroll math
    /// and this overlay both take their overflow / cycle decision from this one
    /// measurement, so they agree on whether — and how far — the title scrolls.
    /// Empty text is width 0.
    static func measuredWidthSkinPx(_ title: String, skin: Skin) -> Int {
        guard !title.isEmpty else { return 0 }
        // scale 1.0 -> the font at its unscaled point size -> width in skin pixels.
        let style = PlaylistTextStyle(skin: skin, scale: 1.0)
        let line = makeLine(title, font: style.font, color: style.normalText)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return Int(width.rounded(.up))
    }

    // MARK: Draw

    /// Draw `title` as a CoreText marquee into `context` (the view's bottom-left
    /// origin POINT space), clipped to the title band, scrolled left by
    /// `offsetSkinPx`.
    ///
    /// When the title FITS the region it is drawn STATIC, left-aligned at the
    /// region's left edge (the offset is ignored) — matching the bitmap `draw`
    /// path. When it OVERFLOWS it scrolls and loops with a fixed gap, mirroring the
    /// bitmap marquee's feel; two copies are laid end to end so the band is always
    /// covered and the loop is seamless. `skinHeight` is the unscaled window height
    /// and `scale` maps skin pixels to context points (possibly fractional — the
    /// CoreText line stays crisp).
    static func draw(
        title: String,
        in context: CGContext,
        skin: Skin,
        scale: Double,
        skinHeight: Int,
        offsetSkinPx: Int
    ) {
        guard !title.isEmpty else { return }

        // The drawn line is resolved at the PRESENTATION scale (crisp at fractional
        // scales); the overflow / cycle DECISION comes from the unscaled skin-pixel
        // measurement so it is identical to the controller's scroll math.
        let style = PlaylistTextStyle(skin: skin, scale: scale)
        let line = makeLine(title, font: style.font, color: style.normalText)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        let clip = scaledFlippedRect(
            x: regionX, y: bandTop, w: regionWidth, h: bandHeight,
            skinHeight: skinHeight, scale: scale
        )
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: clip)

        // Vertically center the ascent/descent band within the clip band (same
        // baseline math the playlist row uses).
        let textHeight = ascent + descent
        let baselineY = clip.minY + (clip.height - textHeight) / 2 + descent
        let s = CGFloat(scale)

        let widthSkinPx = measuredWidthSkinPx(title, skin: skin)
        if widthSkinPx <= regionWidth {
            // Fits: static, left-aligned at the region's left edge (offset ignored).
            context.textPosition = CGPoint(x: CGFloat(regionX) * s, y: baselineY)
            CTLineDraw(line, context)
            return
        }

        // Overflows: one loop unit is the line width plus the gap. Lay two copies
        // end to end, starting shifted left by the normalized offset, so the band
        // is fully covered for any offset and the loop is seamless.
        let cycleSkinPx = widthSkinPx + gapSkinPx
        let normalized = ((offsetSkinPx % cycleSkinPx) + cycleSkinPx) % cycleSkinPx
        var penXSkin = CGFloat(regionX) - CGFloat(normalized)
        for _ in 0..<2 {
            context.textPosition = CGPoint(x: penXSkin * s, y: baselineY)
            CTLineDraw(line, context)
            penXSkin += CGFloat(cycleSkinPx)
        }
    }

    // MARK: Helpers

    private static func makeLine(_ string: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        return CTLineCreateWithAttributedString(attributed)
    }

    /// Map a top-left-origin skin-pixel rect into the bottom-left-origin, scaled
    /// context space — the same flip the playlist track-list drawing uses.
    private static func scaledFlippedRect(
        x: Int, y: Int, w: Int, h: Int,
        skinHeight: Int, scale: Double
    ) -> CGRect {
        let s = CGFloat(scale)
        let bottomY = CGFloat(skinHeight - y - h) * s
        return CGRect(x: CGFloat(x) * s, y: bottomY, width: CGFloat(w) * s, height: CGFloat(h) * s)
    }
}
