import SwiftUI

// MARK: - DwanimTheme

/// The shared colour vocabulary for the default ("Dwanim") skin: the warm gold
/// accent used for the mark and the primary transport button, and the deep
/// indigo -> teal backdrop the glass blurs over.
///
/// Centralising the colours here (rather than scattering literal `Color`s
/// through the views) keeps the "Liquid Glass" look consistent and makes the
/// gold accent a single source of truth: gold = warm `#F6DCA0 -> #C9912F`.
public enum DwanimTheme {

    // MARK: - Gold accent (#F6DCA0 -> #C9912F)

    /// The light end of the gold accent (`#F6DCA0`).
    public static let goldLight = Color(red: 0xF6 / 255, green: 0xDC / 255, blue: 0xA0 / 255)
    /// The deep end of the gold accent (`#C9912F`).
    public static let goldDeep = Color(red: 0xC9 / 255, green: 0x91 / 255, blue: 0x2F / 255)

    /// The warm vertical gold gradient used for the mark and the primary button.
    public static var goldGradient: LinearGradient {
        LinearGradient(
            colors: [goldLight, goldDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Backdrop (deep indigo -> teal)

    /// Deep indigo, the top-left of the backdrop the glass reads against.
    public static let backdropIndigo = Color(red: 0x1A / 255, green: 0x16 / 255, blue: 0x3F / 255)
    /// Teal, the bottom-right of the backdrop.
    public static let backdropTeal = Color(red: 0x10 / 255, green: 0x49 / 255, blue: 0x4E / 255)

    /// The colourful backdrop placed BEHIND the glass so the material blur has
    /// something to read; gold-tinted highlight in the corner for warmth.
    public static var backdrop: LinearGradient {
        LinearGradient(
            colors: [backdropIndigo, backdropTeal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Glass strokes

    /// The subtle ~1px white-ish stroke that gives the glass panels their edge.
    public static let glassStroke = Color.white.opacity(0.18)

    /// A slightly stronger stroke for the emblem tile so the mark's frame reads.
    public static let glassStrokeStrong = Color.white.opacity(0.28)

    // MARK: - Icon plate

    /// A warm gold edge for the app-icon plate. Distinct from the white glass
    /// strokes: the icon's plate is a solid (non-material) face, so a faint gold
    /// rim — rather than a cool white one — keeps the whole icon in the brand's
    /// warm key without depending on a scene behind it.
    public static let goldEdge = goldLight.opacity(0.45)
}
