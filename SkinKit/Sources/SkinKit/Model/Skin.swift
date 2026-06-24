import Foundation

// MARK: - Skin

/// A fully decoded classic `.wsz` skin: the cut sprite bitmaps plus the parsed
/// text-config data, assembled by `SkinLoader`.
///
/// Sprites are **namespaced by sheet**. A flat `name -> bitmap` map would lose
/// data, because the same sprite name legitimately appears in more than one
/// sheet (for example `"play"` is both the transport button in `cbuttons.bmp`
/// and the small status glyph in `playpaus.bmp`). Keying first by the
/// lowercased sheet filename keeps those distinct.
public struct Skin: Sendable {

    // MARK: - Stored state

    /// Sheet filename (lowercased) → sprite name → decoded bitmap. A sheet that
    /// was absent from the archive, or could not be decoded, has no entry here.
    public let sprites: [String: [String: DecodedBitmap]]
    /// The visualization palette from `viscolor.txt`, in document order. Empty
    /// when the file is absent or carried no usable colors.
    public let visColors: [RGBColor]
    /// The playlist-window colors/font from `pledit.txt`, or `nil` when that file
    /// was absent or unreadable.
    public let playlist: PlaylistColors?
    /// The custom window shape from `region.txt`, or `nil` when that file was
    /// absent or unreadable.
    public let region: SkinRegion?

    // MARK: - Init

    public init(
        sprites: [String: [String: DecodedBitmap]],
        visColors: [RGBColor],
        playlist: PlaylistColors?,
        region: SkinRegion?
    ) {
        self.sprites = sprites
        self.visColors = visColors
        self.playlist = playlist
        self.region = region
    }

    // MARK: - Lookup

    /// Looks up a single sprite by its sheet and name, or `nil` if either the
    /// sheet or the sprite within it is absent.
    ///
    /// Sheets are stored under their lowercased filename (see `SkinLoader`), so
    /// the `sheet` argument is lowercased here to match — a caller may pass the
    /// original-cased filename (e.g. `"CBUTTONS.BMP"`). The sprite `name` keys are
    /// authored lowercase in `SpriteCoordinates` and are matched exactly.
    public func sprite(sheet: String, name: String) -> DecodedBitmap? {
        sprites[sheet.lowercased()]?[name]
    }

    /// The vis color at `index`, or `fallback` (default opaque black) if out of
    /// range.
    ///
    /// `visColors` is the raw parsed `viscolor.txt` array, whose length varies in
    /// real files (the nominal 24 is not guaranteed). Render code that indexes
    /// fixed slots should go through this accessor to avoid an out-of-range trap.
    public func visColor(at index: Int, fallback: RGBColor = RGBColor(r: 0, g: 0, b: 0)) -> RGBColor {
        guard index >= 0, index < visColors.count else { return fallback }
        return visColors[index]
    }
}
