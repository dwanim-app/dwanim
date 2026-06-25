import AppKit
import CoreGraphics
import CoreText
import Foundation
import SkinKit

// The skin-driven text style (font + colors + row metrics) for the classic
// playlist (PLEDIT) track list (one primary type per file, §12).
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier (no
// behavior change) alongside the playlist view + controller that consume it, so
// BOTH the dev harness AND the real app target draw the list the same way.

// MARK: - Text style (font + colors from the skin)

/// Resolves the pledit font + colors into CoreText / CoreGraphics types once per
/// draw. The classic playlist text uses the SYSTEM font named in `pledit.txt`;
/// when the skin names no usable font we fall back to a sane monospaced system
/// font so the list is always legible.
struct PlaylistTextStyle {
    /// Unscaled per-row height in skin pixels. The classic list is a compact
    /// fixed row; 12px reads well at the typical small base point size and tiles
    /// the interior cleanly.
    static let rowHeight = 12
    /// Unscaled point size for the list text (skin pixels).
    static let fontPointSize = 9
    /// Unscaled left inset before each title so text does not hug the edge.
    static let leftPadding = 3

    let font: CTFont
    let normalText: CGColor
    let currentText: CGColor
    let selectedBackground: CGColor?

    init(skin: Skin, scale: Int) {
        let pointSize = CGFloat(PlaylistTextStyle.fontPointSize * scale)
        self.font = PlaylistTextStyle.resolveFont(named: skin.playlist?.font, pointSize: pointSize)

        // Classic defaults: green-on-black list, brighter white for the current
        // row, no selection fill unless the skin declares one.
        self.normalText = PlaylistTextStyle.cgColor(
            skin.playlist?.normalText, fallback: SkinKit.RGBColor(r: 0, g: 255, b: 0)
        )
        self.currentText = PlaylistTextStyle.cgColor(
            skin.playlist?.currentText, fallback: SkinKit.RGBColor(r: 255, g: 255, b: 255)
        )
        self.selectedBackground = skin.playlist?.selectedBackground.map { PlaylistTextStyle.cgColor($0) }
    }

    /// Build a `CTFont` for the named system font at `pointSize`, falling back to
    /// a monospaced system font when the name is missing or unresolvable (so the
    /// classic fixed-pitch look is preserved and the list never fails to draw).
    private static func resolveFont(named name: String?, pointSize: CGFloat) -> CTFont {
        if let name, !name.isEmpty {
            let named = CTFontCreateWithName(name as CFString, pointSize, nil)
            // CTFontCreateWithName substitutes a default when the name is unknown;
            // that is acceptable here (we still get a legible font at our size).
            return named
        }
        let monospaced = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        return monospaced as CTFont
    }

    private static func cgColor(
        _ rgb: SkinKit.RGBColor?,
        fallback: SkinKit.RGBColor = SkinKit.RGBColor(r: 0, g: 255, b: 0)
    ) -> CGColor {
        let c = rgb ?? fallback
        return CGColor(
            srgbRed: CGFloat(c.r) / 255,
            green: CGFloat(c.g) / 255,
            blue: CGFloat(c.b) / 255,
            alpha: 1
        )
    }
}
